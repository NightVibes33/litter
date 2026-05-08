import Foundation

struct LocalModelAgentMessage: Identifiable, Equatable {
    enum Role: String, Equatable {
        case user
        case assistant
        case tool
        case system
        case error
    }

    let id: UUID
    var role: Role
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct LocalModelAgentEvent: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case started
        case retry
        case toolCall
        case approval
        case toolResult
        case completed
        case cancelled
        case failed
    }

    let id: UUID
    var kind: Kind
    var title: String
    var detail: String
    var createdAt: Date

    init(id: UUID = UUID(), kind: Kind, title: String, detail: String = "", createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
    }
}

struct LocalModelAgentApprovalState: Identifiable, Equatable {
    var id: String { request.id }
    var request: LocalModelToolApprovalRequest
    var diffPreview: String?
}

struct LocalModelPromptTemplate {
    static func systemPrompt(for model: LocalModelRecord, context: String) -> String {
        let family = model.architecture?.lowercased() ?? model.fileName.lowercased()
        let style: String
        if family.contains("gemma") {
            style = "Use concise Gemma-friendly answers. Emit exactly one JSON tool request when a tool is needed."
        } else if family.contains("qwen") || family.contains("llama") || family.contains("mistral") || family.contains("phi") {
            style = "Use direct coding-agent answers. Emit one valid JSON tool request when a tool is needed."
        } else {
            style = "Use conservative generic assistant formatting. Avoid markdown around tool JSON."
        }
        return """
        You are Litter Local Agent, an offline Codex-style assistant running on-device.
        You can inspect fakefs files with read-only tools. Shell and write tools require user approval.
        Prefer small, reversible file edits. When editing, call write_file with the full new UTF-8 file content.
        Model: \(model.fileName)
        Prompt style: \(style)

        Context pack:
        \(context.isEmpty ? "No files selected." : context)
        """
    }
}

enum LocalModelContextBuilder {
    static func build(paths: [String], maxFiles: Int = 24, maxBytesPerFile: Int64 = 12_000) async -> String {
        var sections: [String] = []
        var remaining = maxFiles
        for rawPath in paths {
            guard remaining > 0 else { break }
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            let files = await candidateFiles(for: path, limit: remaining)
            for file in files.prefix(remaining) {
                if let text = try? await IshFS.readTextFile(path: file, maxBytes: maxBytesPerFile) {
                    sections.append("""
                    --- file: \(file) ---
                    \(text)
                    """)
                    remaining -= 1
                }
            }
        }
        return sections.joined(separator: "\n\n")
    }

    private static func candidateFiles(for path: String, limit: Int) async -> [String] {
        let quoted = IshFS.shellQuote(path)
        let probe = await IshFS.run("if [ -d \(quoted) ]; then find \(quoted) -maxdepth 3 -type f | head -n \(limit); elif [ -f \(quoted) ]; then printf '%s\\n' \(quoted); fi")
        guard probe.exitCode == 0 else { return [] }
        return probe.output.split(separator: "\n").map(String.init)
    }
}

@MainActor
final class LocalModelAgentStore: ObservableObject {
    @Published private(set) var messages: [LocalModelAgentMessage] = []
    @Published private(set) var events: [LocalModelAgentEvent] = []
    @Published private(set) var isRunning = false
    @Published var contextPathsText = "/root"
    @Published var pendingApproval: LocalModelAgentApprovalState?
    @Published private(set) var lastError: String?

    private var activeTask: Task<Void, Never>?
    private var approvalContinuations: [String: CheckedContinuation<LocalModelToolApprovalDecision, Never>] = [:]
    private var lastPrompt: String?
    private var lastModel: LocalModelRecord?

    func send(prompt: String, model: LocalModelRecord) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        lastPrompt = trimmed
        lastModel = model
        messages.append(LocalModelAgentMessage(role: .user, text: trimmed))
        run(prompt: trimmed, model: model)
    }

    func retry() {
        guard let lastPrompt, let lastModel, !isRunning else { return }
        run(prompt: lastPrompt, model: lastModel)
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isRunning = false
        pendingApproval = nil
        approvalContinuations.values.forEach { $0.resume(returning: .denied) }
        approvalContinuations.removeAll()
        Task { await LocalLlamaRuntime.shared.cancel() }
        events.append(LocalModelAgentEvent(kind: .cancelled, title: "Cancelled", detail: "Local generation was stopped."))
    }

    func resolveApproval(_ decision: LocalModelToolApprovalDecision) {
        guard let approval = pendingApproval else { return }
        pendingApproval = nil
        approvalContinuations.removeValue(forKey: approval.id)?.resume(returning: decision)
    }

    private func run(prompt: String, model: LocalModelRecord) {
        isRunning = true
        lastError = nil
        let contextPaths = contextPathsText
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map(String.init)
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let context = await LocalModelContextBuilder.build(paths: contextPaths)
                let runtimeSettings = AIProviderStore.shared.runtimeSettings(for: model)
                let system = runtimeSettings.systemPromptOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? LocalModelPromptTemplate.systemPrompt(for: model, context: context)
                    : """
                    \(runtimeSettings.systemPromptOverride)

                    Context pack:
                    \(context.isEmpty ? "No files selected." : context)
                    """
                let turboAvailable = AIProviderStore.shared.turboQuantAvailability.isAvailable
                let options = LocalLlamaGenerationOptions.from(
                    settings: runtimeSettings,
                    capability: .current(),
                    turboQuantAvailable: turboAvailable
                )
                let request = LocalLlamaGenerationRequest(
                    model: model,
                    projector: nil,
                    messages: [
                        LocalLlamaMessage(role: .system, text: system),
                        LocalLlamaMessage(role: .user, text: prompt)
                    ],
                    maxTokens: runtimeSettings.maxOutputTokens,
                    temperature: runtimeSettings.temperature,
                    tools: runtimeSettings.toolUseMode == .off ? [] : LocalModelToolLoop.defaultToolSpecs,
                    toolPolicy: .readOnly,
                    options: options,
                    approvalHandler: { [weak self] approval in
                        await self?.requestApproval(approval) ?? .denied
                    }
                )
                var assistantText = ""
                let assistantId = UUID()
                messages.append(LocalModelAgentMessage(id: assistantId, role: .assistant, text: ""))
                for try await event in await LocalLlamaRuntime.shared.generateEvents(request) {
                    try Task.checkCancellation()
                    handle(event, assistantId: assistantId, assistantText: &assistantText)
                }
                isRunning = false
                activeTask = nil
            } catch is CancellationError {
                cancel()
            } catch {
                isRunning = false
                activeTask = nil
                lastError = error.localizedDescription
                events.append(LocalModelAgentEvent(kind: .failed, title: "Generation failed", detail: error.localizedDescription))
                messages.append(LocalModelAgentMessage(role: .error, text: error.localizedDescription))
            }
        }
    }

    private func handle(_ event: LocalLlamaStreamEvent, assistantId: UUID, assistantText: inout String) {
        switch event {
        case .started(let modelName, let contextTokens):
            events.append(LocalModelAgentEvent(kind: .started, title: "Started \(modelName)", detail: "Context: \(contextTokens) tokens"))
        case .token(let token):
            assistantText += token
            updateAssistant(id: assistantId, text: assistantText)
        case .retry(let attempt, let reason):
            events.append(LocalModelAgentEvent(kind: .retry, title: "Retry \(attempt)", detail: reason))
        case .toolCall(let call):
            events.append(LocalModelAgentEvent(kind: .toolCall, title: "Tool: \(call.name)", detail: call.arguments.description))
        case .approvalRequired(let approval):
            events.append(LocalModelAgentEvent(kind: .approval, title: "Approval required", detail: approval.reason))
        case .toolResult(let result):
            events.append(LocalModelAgentEvent(kind: .toolResult, title: result.success ? "Tool completed" : "Tool failed", detail: result.output))
            messages.append(LocalModelAgentMessage(role: .tool, text: "\(result.toolName): \(result.output)"))
        case .completed(let text):
            if !text.isEmpty { updateAssistant(id: assistantId, text: text) }
            events.append(LocalModelAgentEvent(kind: .completed, title: "Completed"))
        }
    }

    private func updateAssistant(id: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
    }

    private func requestApproval(_ request: LocalModelToolApprovalRequest) async -> LocalModelToolApprovalDecision {
        let diff = await diffPreview(for: request)
        return await withCheckedContinuation { continuation in
            approvalContinuations[request.id] = continuation
            pendingApproval = LocalModelAgentApprovalState(request: request, diffPreview: diff)
        }
    }

    private func diffPreview(for request: LocalModelToolApprovalRequest) async -> String? {
        guard request.risk == .write,
              let path = request.call.arguments["path"],
              let newText = request.call.arguments["text"] else { return nil }
        let oldText = (try? await IshFS.readTextFile(path: path, maxBytes: 24_000)) ?? ""
        return LocalModelDiffPreview.make(old: oldText, new: newText, path: path)
    }
}

enum LocalModelDiffPreview {
    static func make(old: String, new: String, path: String) -> String {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output = ["--- \(path)", "+++ \(path)"]
        let count = max(oldLines.count, newLines.count)
        for index in 0..<min(count, 80) {
            let oldLine = index < oldLines.count ? oldLines[index] : nil
            let newLine = index < newLines.count ? newLines[index] : nil
            if oldLine == newLine {
                output.append("  \(oldLine ?? "")")
            } else {
                if let oldLine { output.append("- \(oldLine)") }
                if let newLine { output.append("+ \(newLine)") }
            }
        }
        if count > 80 { output.append("... diff truncated ...") }
        return output.joined(separator: "\n")
    }
}
