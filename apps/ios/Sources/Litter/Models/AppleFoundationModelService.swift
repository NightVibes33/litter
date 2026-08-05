import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleFoundationModelRuntimeStatus: Equatable, Sendable {
    case available
    case unavailable(String)

    var summary: String {
        switch self {
        case .available:
            return "Ready on this device"
        case .unavailable(let reason):
            return reason
        }
    }
}

enum AppleFoundationModelRuntimeError: LocalizedError {
    case unavailable(String)
    case emptyPrompt
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        case .emptyPrompt:
            return "Enter a message first."
        case .emptyResponse:
            return "The on-device model returned an empty response."
        }
    }
}

/// Direct access to Apple's on-device language model. This service never
/// requires an API key, a remote endpoint, or a network connection.
actor AppleFoundationModelService {
    static let shared = AppleFoundationModelService()

    private let defaultInstructions = """
    You are PocketKernel, a private on-device assistant running on an iPhone or iPad.
    Be concise, accurate, and explicit about uncertainty. Never claim an action ran
    unless a tool or runtime returned a successful result. When an action requires
    shell, file, network, or device access, describe the proposed action for approval.
    """

    func status() -> AppleFoundationModelRuntimeStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
                ? .available
                : .unavailable("Apple Intelligence is not ready on this device.")
        }
        #endif
        return .unavailable("Apple Foundation Models requires iOS 26 or later on an eligible device.")
    }

    func respond(
        to rawPrompt: String,
        instructions: String? = nil
    ) async throws -> String {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw AppleFoundationModelRuntimeError.emptyPrompt
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                throw AppleFoundationModelRuntimeError.unavailable(
                    "Apple Intelligence is disabled, still downloading, or unavailable on this device."
                )
            }

            let session = LanguageModelSession(
                model: model,
                instructions: instructions ?? defaultInstructions
            )
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw AppleFoundationModelRuntimeError.emptyResponse
            }
            return text
        }
        #endif

        throw AppleFoundationModelRuntimeError.unavailable(
            "Apple Foundation Models requires iOS 26 or later on an eligible device."
        )
    }
}
