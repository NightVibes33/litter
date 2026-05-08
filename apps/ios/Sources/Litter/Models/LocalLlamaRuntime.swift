import Foundation

enum LocalLlamaRuntimeError: LocalizedError {
    case unavailable
    case missingModel
    case unsupportedAttachment(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The on-device llama.cpp runtime is not linked in this build."
        case .missingModel:
            return "The local model file is missing."
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
