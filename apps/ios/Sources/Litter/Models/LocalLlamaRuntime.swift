import Foundation

enum LocalLlamaRuntimeError: LocalizedError {
    case unavailable
    case missingModel
    case unsupportedAttachment(String)
    case toolLoopUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The on-device llama.cpp token generator is not linked in this build."
        case .missingModel:
            return "The local model file is missing."
        case .toolLoopUnavailable:
            return "The local model tool loop is available, but llama.cpp token generation is not connected yet."
        case .unsupportedAttachment(let message):
            return message
        }
    }
}

struct LocalLlamaMessage: Equatable {
    enum Role: String {
        case system
        case user
        case assistant
        case tool
    }

    var role: Role
    var text: String
}

struct LocalLlamaRetryPolicy: Equatable {
    var maxAttempts: Int
    var retryDelayNanoseconds: UInt64

    static let disabled = LocalLlamaRetryPolicy(maxAttempts: 1, retryDelayNanoseconds: 0)
    static let localDefault = LocalLlamaRetryPolicy(maxAttempts: 2, retryDelayNanoseconds: 250_000_000)
}

struct LocalLlamaGenerationOptions: Equatable {
    var contextTokens: Int
    var allowToolCalls: Bool
    var maxToolRounds: Int
    var retryPolicy: LocalLlamaRetryPolicy
    var topP: Double
    var topK: Int
    var repeatPenalty: Double
    var preferredThreadCount: Int
    var metalEnabled: Bool
    var cpuFallbackAllowed: Bool
    var streamingEnabled: Bool
    var kvCacheMode: LocalModelKVCacheMode

    static func defaults(for capability: DeviceCapabilityProfile = .current()) -> LocalLlamaGenerationOptions {
        from(settings: .defaults(for: capability), capability: capability, turboQuantAvailable: false)
    }

    static func from(
        settings: LocalModelRuntimeSettings,
        capability: DeviceCapabilityProfile = .current(),
        turboQuantAvailable: Bool
    ) -> LocalLlamaGenerationOptions {
        let safe = settings.sanitized(for: capability, turboQuantAvailable: turboQuantAvailable)
        return LocalLlamaGenerationOptions(
            contextTokens: safe.contextTokens,
            allowToolCalls: safe.toolUseMode != .off,
            maxToolRounds: safe.maxToolRounds,
            retryPolicy: .localDefault,
            topP: safe.topP,
            topK: safe.topK,
            repeatPenalty: safe.repeatPenalty,
            preferredThreadCount: safe.preferredThreadCount,
            metalEnabled: safe.metalEnabled,
            cpuFallbackAllowed: safe.cpuFallbackAllowed,
            streamingEnabled: safe.streamingEnabled,
            kvCacheMode: safe.kvCacheMode
        )
    }
}

struct LocalLlamaGenerationRequest {
    typealias ApprovalHandler = @Sendable (LocalModelToolApprovalRequest) async -> LocalModelToolApprovalDecision

    var model: LocalModelRecord
    var projector: LocalModelRecord?
    var messages: [LocalLlamaMessage]
    var maxTokens: Int
    var temperature: Double
    var tools: [LocalModelToolSpec] = LocalModelToolLoop.defaultToolSpecs
    var toolPolicy: LocalModelToolPolicy = .readOnly
    var options: LocalLlamaGenerationOptions = .defaults()
    var approvalHandler: ApprovalHandler?
}

enum LocalLlamaStreamEvent: Equatable {
    case started(modelName: String, contextTokens: Int)
    case token(String)
    case retry(attempt: Int, reason: String)
    case toolCall(LocalModelToolCall)
    case approvalRequired(LocalModelToolApprovalRequest)
    case toolResult(LocalModelToolResult)
    case completed(String)
}

private final class LocalLlamaTokenBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func append(_ token: String) {
        lock.lock()
        storage += token
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// App-side contract for the native llama.cpp engine.
///
/// The repository now has the download/import layer, guarded fakefs tools,
/// approval events, retries, and stream state. A production build still needs
/// the native llama.cpp Swift/C bridge to call `configureTokenGenerator`.
struct LocalLlamaRuntimeCapabilities: Equatable {
    var isAvailable: Bool
    var turboQuant: TurboQuantAvailability
    var supportedKVCacheModes: [LocalModelKVCacheMode]

    static let unavailable = LocalLlamaRuntimeCapabilities(
        isAvailable: false,
        turboQuant: .unavailable("The linked llama.cpp bridge does not report TurboQuant support in this build."),
        supportedKVCacheModes: [.automatic, .f16, .q8, .q4]
    )
}

actor LocalLlamaRuntime {
    typealias TokenGenerator = @Sendable (
        _ request: LocalLlamaGenerationRequest,
        _ messages: [LocalLlamaMessage],
        _ onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String
    typealias CancellationHandler = @Sendable () -> Void

    static let shared = LocalLlamaRuntime()

    private var tokenGenerator: TokenGenerator?
    private var cancellationHandler: CancellationHandler?
    private var runtimeCapabilities = LocalLlamaRuntimeCapabilities.unavailable

    private init() {}

    func configureTokenGenerator(_ generator: TokenGenerator?) {
        tokenGenerator = generator
    }

    func configureCancellationHandler(_ handler: CancellationHandler?) {
        cancellationHandler = handler
    }

    func configureCapabilities(_ capabilities: LocalLlamaRuntimeCapabilities) {
        runtimeCapabilities = capabilities
    }

    func capabilities() -> LocalLlamaRuntimeCapabilities {
        runtimeCapabilities
    }

    func toolSystemMessage(for request: LocalLlamaGenerationRequest) -> LocalLlamaMessage {
        LocalLlamaMessage(role: .system, text: LocalModelToolLoop.systemInstructions(for: request.tools))
    }

    func approvalRequest(for call: LocalModelToolCall) -> LocalModelToolApprovalRequest {
        LocalModelToolLoop.approvalRequest(for: call)
    }

    func executeToolCall(_ call: LocalModelToolCall, policy: LocalModelToolPolicy = .readOnly) async -> LocalModelToolResult {
        await LocalModelToolLoop.execute(call, policy: policy)
    }

    func generate(_ request: LocalLlamaGenerationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in self.generateEvents(request) {
                        if case .token(let token) = event {
                            continuation.yield(token)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func generateEvents(_ request: LocalLlamaGenerationRequest) -> AsyncThrowingStream<LocalLlamaStreamEvent, Error> {
        let generator = tokenGenerator
        return AsyncThrowingStream { continuation in
            let task = Task {
                guard FileManager.default.fileExists(atPath: request.model.fileURL.path) else {
                    continuation.finish(throwing: LocalLlamaRuntimeError.missingModel)
                    return
                }
                guard let generator else {
                    continuation.finish(throwing: LocalLlamaRuntimeError.unavailable)
                    return
                }

                continuation.yield(.started(modelName: request.model.fileName, contextTokens: request.options.contextTokens))
                do {
                    let text = try await Self.runToolAwareGeneration(
                        request: request,
                        generator: generator,
                        continuation: continuation
                    )
                    continuation.yield(.completed(text))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func cancel() async {
        cancellationHandler?()
    }

    func unload() async {
        cancellationHandler?()
        tokenGenerator = nil
        cancellationHandler = nil
    }

    func smokeTest(_ model: LocalModelRecord, maxTokens: Int = 8) async throws -> String {
        let request = LocalLlamaGenerationRequest(
            model: model,
            projector: nil,
            messages: [
                LocalLlamaMessage(role: .system, text: "You are validating that this local model can run. Reply with one short sentence."),
                LocalLlamaMessage(role: .user, text: "Say: model ready")
            ],
            maxTokens: maxTokens,
            temperature: 0,
            tools: [],
            toolPolicy: .readOnly,
            options: LocalLlamaGenerationOptions(
                contextTokens: max(512, min(DeviceCapabilityProfile.current().recommendedContextTokens, 2_048)),
                allowToolCalls: false,
                maxToolRounds: 0,
                retryPolicy: .disabled,
                topP: 0.9,
                topK: 40,
                repeatPenalty: 1.08,
                preferredThreadCount: max(1, min(4, ProcessInfo.processInfo.processorCount)),
                metalEnabled: DeviceCapabilityProfile.current().hasMetal,
                cpuFallbackAllowed: false,
                streamingEnabled: true,
                kvCacheMode: .automatic
            ),
            approvalHandler: nil
        )
        var output = ""
        for try await token in generate(request) {
            output += token
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LocalLlamaRuntimeError.toolLoopUnavailable }
        return trimmed
    }

    private static func runToolAwareGeneration(
        request: LocalLlamaGenerationRequest,
        generator: TokenGenerator,
        continuation: AsyncThrowingStream<LocalLlamaStreamEvent, Error>.Continuation
    ) async throws -> String {
        var messages = request.messages
        if request.options.allowToolCalls, !request.tools.isEmpty {
            messages.insert(LocalLlamaMessage(role: .system, text: LocalModelToolLoop.systemInstructions(for: request.tools)), at: 0)
        }

        var finalText = ""
        var lastError: Error?
        let attempts = max(1, request.options.retryPolicy.maxAttempts)

        for attempt in 1...attempts {
            do {
                let buffer = LocalLlamaTokenBuffer()
                let generated = try await generator(request, messages) { token in
                    buffer.append(token)
                    continuation.yield(.token(token))
                }
                finalText = generated.isEmpty ? buffer.text : generated
                break
            } catch {
                lastError = error
                guard attempt < attempts else { throw error }
                continuation.yield(.retry(attempt: attempt + 1, reason: error.localizedDescription))
                if request.options.retryPolicy.retryDelayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: request.options.retryPolicy.retryDelayNanoseconds)
                }
            }
        }

        if finalText.isEmpty, let lastError {
            throw lastError
        }

        guard request.options.allowToolCalls else { return finalText }

        var rounds = 0
        while rounds < request.options.maxToolRounds {
            try Task.checkCancellation()
            let calls = LocalModelToolLoop.parseToolCalls(from: finalText)
            if calls.isEmpty {
                guard LocalModelToolLoop.looksLikeMalformedToolRequest(finalText) else { break }
                rounds += 1
                continuation.yield(.retry(attempt: rounds, reason: "Malformed local tool JSON; asking model to resend exactly one valid tool object."))
                messages.append(LocalLlamaMessage(role: .assistant, text: finalText))
                messages.append(LocalLlamaMessage(role: .system, text: "Your previous response looked like a tool request but was not valid JSON. Reply with exactly one JSON object like {\"tool\":\"read_file\",\"arguments\":{\"path\":\"/root/file.txt\"}} or answer normally without tool syntax."))
                let buffer = LocalLlamaTokenBuffer()
                let generated = try await generator(request, messages) { token in
                    buffer.append(token)
                    continuation.yield(.token(token))
                }
                finalText = generated.isEmpty ? buffer.text : generated
                continue
            }
            rounds += 1

            for call in calls {
                try Task.checkCancellation()
                continuation.yield(.toolCall(call))
                let policy = await approvedPolicy(for: call, request: request, continuation: continuation)
                let result = await LocalModelToolLoop.execute(call, policy: policy)
                continuation.yield(.toolResult(result))
                messages.append(LocalLlamaMessage(role: .assistant, text: finalText))
                messages.append(LocalLlamaMessage(role: .tool, text: toolResultMessage(result)))
                if !result.success {
                    messages.append(LocalLlamaMessage(role: .system, text: "The previous local tool failed. Recover safely: explain the failure, request a narrower read-only tool, or produce a final answer. Do not claim the failed tool succeeded."))
                    continuation.yield(.retry(attempt: rounds, reason: "Recovering from failed \(result.toolName) tool."))
                }
            }

            try Task.checkCancellation()
            let buffer = LocalLlamaTokenBuffer()
            let generated = try await generator(request, messages) { token in
                buffer.append(token)
                continuation.yield(.token(token))
            }
            finalText = generated.isEmpty ? buffer.text : generated
        }

        return finalText
    }

    private static func approvedPolicy(
        for call: LocalModelToolCall,
        request: LocalLlamaGenerationRequest,
        continuation: AsyncThrowingStream<LocalLlamaStreamEvent, Error>.Continuation
    ) async -> LocalModelToolPolicy {
        let approval = LocalModelToolLoop.approvalRequest(for: call)
        guard approval.requiresUserApproval else { return request.toolPolicy }
        continuation.yield(.approvalRequired(approval))
        guard let decision = await request.approvalHandler?(approval), decision.isApproved else {
            return .readOnly
        }
        return decision.policy
    }

    private static func toolResultMessage(_ result: LocalModelToolResult) -> String {
        let payload: [String: Any] = [
            "tool_result": [
                "id": result.callId,
                "tool": result.toolName,
                "success": result.success,
                "output": result.output
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return result.output
        }
        return text
    }
}
