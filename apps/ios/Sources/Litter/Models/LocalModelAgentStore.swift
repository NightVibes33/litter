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

enum LocalModelRunPhase: Equatable {
    case idle
    case preparingContext
    case generating
    case waitingForApproval(String)
    case runningTool(String)
    case retrying(String)
    case recovering(String)
    case completed
    case cancelled
    case failed(String)

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .preparingContext: return "Preparing context"
        case .generating: return "Generating"
        case .waitingForApproval(let tool): return "Waiting for approval: \(tool)"
        case .runningTool(let tool): return "Running tool: \(tool)"
        case .retrying(let reason): return "Retrying: \(reason)"
        case .recovering(let reason): return "Recovering: \(reason)"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .failed(let reason): return "Failed: \(reason)"
        }
    }
}

struct LocalModelContextBundle: Equatable {
    var text: String
    var summary: String
    var repoMap: String
    var fileCount: Int
    var byteCount: Int
    var truncatedFiles: [String]
}

struct LocalModelPromptTemplate {
    static func systemPrompt(for model: LocalModelRecord, context: String, skills: String) -> String {
        let family = promptFamily(for: model)
        return """
        You are Litter Local Agent, an offline Codex-style assistant running on-device.
        Model: \(model.fileName)
        Model family guidance: \(family)

        Installed skill instructions:
        \(skills.isEmpty ? "No user-installed skills are enabled." : skills)

        Tool contract:
        - Request tools with exactly one JSON object and no markdown.
        - Use read-only tools before edits: repo_map, search_files, grep_text, list_dir, read_file.
        - For small edits use replace_text. Use write_file only when replacing the full file is safer.
        - Shell and write/edit tools require user approval. If denied, recover with a safer read-only plan.
        - If a tool fails, explain the recovery path or request a narrower tool call.
        - Never pretend a tool ran. Only cite observed tool output.

        Editing contract:
        - Prefer minimal, reversible edits.
        - Preserve unrelated content.
        - After an edit, summarize changed paths and any verification still needed.

        Context pack:
        \(context.isEmpty ? "No files selected." : context)
        """
    }

    private static func promptFamily(for model: LocalModelRecord) -> String {
        let family = model.architecture?.lowercased() ?? model.fileName.lowercased()
        if family.contains("gemma") {
            return "Gemma: concise instructions, one JSON tool call at a time, avoid decorative markdown around tool JSON."
        }
        if family.contains("qwen") {
            return "Qwen: strong code/task following, keep tool arguments exact and recover explicitly after failures."
        }
        if family.contains("llama") {
            return "Llama: direct coding-agent style, separate analysis from final answer, emit strict tool JSON when needed."
        }
        if family.contains("mistral") {
            return "Mistral: compact stepwise reasoning, prefer small tool calls and verify assumptions from files."
        }
        if family.contains("phi") {
            return "Phi: short context-sensitive answers, avoid multi-tool batches, ask for narrower context when unsure."
        }
        return "On-device AI is disabled in this build; use a hosted or computer endpoint."
    }
}

enum LocalModelContextBuilder {
    static func build(paths: [String], maxFiles: Int = 24, maxBytesPerFile: Int64 = 12_000) async -> String {
        await buildBundle(paths: paths, maxFiles: maxFiles, maxBytesPerFile: maxBytesPerFile).text
    }

    static func buildBundle(
        paths: [String],
        maxFiles: Int = 24,
        maxBytesPerFile: Int64 = 12_000,
        includeRepoMap: Bool = true
    ) async -> LocalModelContextBundle {
        let normalized = paths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let requestedPaths = normalized.isEmpty ? ["/root"] : normalized
        var sections: [String] = []
        var byteCount = 0
        var fileCount = 0
        var truncatedFiles: [String] = []
        var remaining = maxFiles

        let mapText = includeRepoMap ? await repoMap(for: requestedPaths, maxEntries: 160) : ""
        if !mapText.isEmpty {
            sections.append("""
            --- repo map ---
            \(mapText)
            """)
        }

        for rawPath in requestedPaths {
            guard remaining > 0 else { break }
            let files = await candidateFiles(for: rawPath, limit: remaining)
            for file in files.prefix(remaining) {
                let result = await readPrefix(path: file, maxBytes: maxBytesPerFile)
                guard !result.text.isEmpty else { continue }
                sections.append("""
                --- file: \(file)\(result.truncated ? " (truncated)" : "") ---
                \(result.text)
                """)
                fileCount += 1
                byteCount += result.byteCount
                if result.truncated { truncatedFiles.append(file) }
                remaining -= 1
            }
        }

        let summary = "Context: \(fileCount) files, ~\(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)), \(truncatedFiles.count) truncated."
        return LocalModelContextBundle(
            text: sections.joined(separator: "\n\n"),
            summary: summary,
            repoMap: mapText,
            fileCount: fileCount,
            byteCount: byteCount,
            truncatedFiles: truncatedFiles
        )
    }

    private static func candidateFiles(for path: String, limit: Int) async -> [String] {
        let quoted = IshFS.shellQuote(path)
        let probe = await IshFS.run("if [ -d \(quoted) ]; then find \(quoted) -maxdepth 3 -type f 2>/dev/null | grep -Ev '/([.]git|node_modules|DerivedData|[.]build)/' | head -n \(limit); elif [ -f \(quoted) ]; then printf '%s\n' \(quoted); fi")
        guard probe.exitCode == 0 else { return [] }
        return probe.output.split(separator: "\n").map(String.init)
    }

    private static func repoMap(for paths: [String], maxEntries: Int) async -> String {
        var output: [String] = []
        for path in paths.prefix(3) {
            let quoted = IshFS.shellQuote(path)
            let result = await IshFS.run("if [ -d \(quoted) ]; then find \(quoted) -maxdepth 3 -print 2>/dev/null | grep -Ev '/([.]git|node_modules|DerivedData|[.]build)(/|$)' | sed 's#^#- #' | head -n \(maxEntries); elif [ -f \(quoted) ]; then printf -- '- %s\n' \(quoted); fi")
            if result.exitCode == 0, !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output.append(result.output)
            }
        }
        return output.joined(separator: "\n")
    }

    private static func readPrefix(path: String, maxBytes: Int64) async -> (text: String, byteCount: Int, truncated: Bool) {
        let quoted = IshFS.shellQuote(path)
        let sizeResult = await IshFS.run("wc -c < \(quoted) 2>/dev/null || exit 2")
        let size = Int64(sizeResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let read = await IshFS.run("head -c \(maxBytes) \(quoted) 2>/dev/null")
        guard read.exitCode == 0 else { return ("", 0, false) }
        return (read.output, min(Int(maxBytes), read.output.utf8.count), size > maxBytes)
    }
}

@MainActor
final class LocalModelAgentStore: ObservableObject {
    @Published private(set) var messages: [LocalModelAgentMessage] = []
    @Published private(set) var events: [LocalModelAgentEvent] = []
    @Published private(set) var isRunning = false
    @Published private(set) var phase: LocalModelRunPhase = .idle
    @Published private(set) var contextBudgetSummary = "No context prepared yet."
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
        phase = .cancelled
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
        phase = .preparingContext
        lastError = nil
        let contextPaths = contextPathsText
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map(String.init)
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let contextBundle = await LocalModelContextBuilder.buildBundle(paths: contextPaths)
                contextBudgetSummary = contextBundle.summary
                let context = contextBundle.text
                let skillContext = InstalledSkillCatalog.localModelSkillContext()
                phase = .generating
                let runtimeSettings = AIProviderStore.shared.effectiveRuntimeSettings(for: model)
                let system = runtimeSettings.systemPromptOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? LocalModelPromptTemplate.systemPrompt(for: model, context: context, skills: skillContext)
                    : """
                    \(runtimeSettings.systemPromptOverride)

                    Installed skill instructions:
                    \(skillContext.isEmpty ? "No user-installed skills are enabled." : skillContext)

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
                phase = .completed
                activeTask = nil
            } catch is CancellationError {
                cancel()
            } catch {
                isRunning = false
                phase = .failed(error.localizedDescription)
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
            phase = .generating
            events.append(LocalModelAgentEvent(kind: .started, title: "Started \(modelName)", detail: "Context: \(contextTokens) tokens"))
        case .token(let token):
            phase = .generating
            assistantText += token
            updateAssistant(id: assistantId, text: assistantText)
        case .retry(let attempt, let reason):
            phase = .retrying(reason)
            events.append(LocalModelAgentEvent(kind: .retry, title: "Retry \(attempt)", detail: reason))
        case .toolCall(let call):
            phase = .runningTool(call.name)
            events.append(LocalModelAgentEvent(kind: .toolCall, title: "Tool: \(call.name)", detail: call.arguments.description))
        case .approvalRequired(let approval):
            phase = .waitingForApproval(approval.call.name)
            events.append(LocalModelAgentEvent(kind: .approval, title: "Approval required", detail: approval.reason))
        case .toolResult(let result):
            phase = result.success ? .generating : .recovering(result.output)
            events.append(LocalModelAgentEvent(kind: .toolResult, title: result.success ? "Tool completed" : "Tool failed", detail: result.output))
            messages.append(LocalModelAgentMessage(role: .tool, text: "\(result.toolName): \(result.output)"))
        case .completed(let text):
            phase = .completed
            if !text.isEmpty { updateAssistant(id: assistantId, text: text) }
            events.append(LocalModelAgentEvent(kind: .completed, title: "Completed"))
        }
    }

    private func updateAssistant(id: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
    }

    private func requestApproval(_ request: LocalModelToolApprovalRequest) async -> LocalModelToolApprovalDecision {
        phase = .waitingForApproval(request.call.name)
        let diff = await diffPreview(for: request)
        return await withCheckedContinuation { continuation in
            approvalContinuations[request.id] = continuation
            pendingApproval = LocalModelAgentApprovalState(request: request, diffPreview: diff)
        }
    }

    private func diffPreview(for request: LocalModelToolApprovalRequest) async -> String? {
        guard request.risk == .write,
              let path = request.call.arguments["path"] else { return nil }
        let oldText = (try? await IshFS.readTextFile(path: path, maxBytes: 24_000)) ?? ""
        if request.call.name == "replace_text",
           let oldFragment = request.call.arguments["old_text"],
           let newFragment = request.call.arguments["new_text"] {
            return LocalModelDiffPreview.make(old: oldText, new: oldText.replacingOccurrences(of: oldFragment, with: newFragment), path: path)
        }
        guard let newText = request.call.arguments["text"] else { return nil }
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
