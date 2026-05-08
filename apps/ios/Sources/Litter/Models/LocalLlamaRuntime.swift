import Foundation

enum LocalLlamaRuntimeError: LocalizedError {
    case unavailable
    case missingModel
    case unsupportedAttachment(String)
    case toolLoopUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The on-device llama.cpp runtime is not linked in this build."
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
    }

    var role: Role
    var text: String
}

struct LocalLlamaGenerationRequest {
    var model: LocalModelRecord
    var projector: LocalModelRecord?
    var messages: [LocalLlamaMessage]
    var maxTokens: Int
    var temperature: Double
    var tools: [LocalModelToolSpec] = LocalModelToolLoop.defaultToolSpecs
    var toolPolicy: LocalModelToolPolicy = .readOnly
}

/// App-side contract for the native llama.cpp engine.
///
/// The current repository does not include a C/Swift bridge for llama.cpp yet,
/// so production builds expose a clear unavailable error instead of silently
/// pretending local inference is wired. The downloader and model library can
/// still be used to prepare GGUF files.
actor LocalLlamaRuntime {
    static let shared = LocalLlamaRuntime()

    private init() {}

    func toolSystemMessage(for request: LocalLlamaGenerationRequest) -> LocalLlamaMessage {
        LocalLlamaMessage(role: .system, text: LocalModelToolLoop.systemInstructions(for: request.tools))
    }

    func executeToolCall(_ call: LocalModelToolCall, policy: LocalModelToolPolicy = .readOnly) async -> LocalModelToolResult {
        await LocalModelToolLoop.execute(call, policy: policy)
    }

    func generate(_ request: LocalLlamaGenerationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard FileManager.default.fileExists(atPath: request.model.fileURL.path) else {
                continuation.finish(throwing: LocalLlamaRuntimeError.missingModel)
                return
            }
            continuation.finish(throwing: LocalLlamaRuntimeError.unavailable)
        }
    }

    func cancel() async {}

    func unload() async {}
}
