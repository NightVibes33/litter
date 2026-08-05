import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleFoundationModelAvailability: Equatable, Sendable {
    case available
    case unsupportedOperatingSystem
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable(String)

    var isAvailable: Bool {
        self == .available
    }

    var summary: String {
        switch self {
        case .available:
            return "Available on this device"
        case .unsupportedOperatingSystem:
            return "Requires iOS 26, iPadOS 26, or macOS 26"
        case .deviceNotEligible:
            return "This device does not support Apple Intelligence"
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings"
        case .modelNotReady:
            return "The on-device model is still downloading or preparing"
        case .unavailable(let message):
            return message
        }
    }
}

enum AppleFoundationModelsProviderError: LocalizedError, Equatable {
    case unavailable(AppleFoundationModelAvailability)
    case emptyPrompt

    var errorDescription: String? {
        switch self {
        case .unavailable(let availability):
            return availability.summary
        case .emptyPrompt:
            return "The prompt is empty."
        }
    }
}

/// The first-class PocketKernel model provider.
///
/// This actor never sends prompts to a network endpoint. On supported devices it
/// creates an Apple Foundation Models session and returns the on-device response.
actor AppleFoundationModelsProvider {
    static let shared = AppleFoundationModelsProvider()

    static let defaultInstructions = """
    You are PocketKernel, a private on-device assistant running inside Litter.
    Help the user understand and operate their local workspace. Never claim that
    a command has run until the execution runtime reports success. When an action
    could modify files, access the network, install software, or delete data,
    explain the action clearly and require explicit user approval before execution.
    """

    func availability() -> AppleFoundationModelAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                return .modelNotReady
            case .unavailable(let reason):
                return .unavailable(String(describing: reason))
            }
        }
        #endif

        return .unsupportedOperatingSystem
    }

    func respond(
        to prompt: String,
        instructions: String = AppleFoundationModelsProvider.defaultInstructions
    ) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw AppleFoundationModelsProviderError.emptyPrompt
        }

        let currentAvailability = availability()
        guard currentAvailability.isAvailable else {
            throw AppleFoundationModelsProviderError.unavailable(currentAvailability)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: instructions
            )
            return try await session.respond(to: trimmedPrompt).content
        }
        #endif

        throw AppleFoundationModelsProviderError.unavailable(.unsupportedOperatingSystem)
    }
}
