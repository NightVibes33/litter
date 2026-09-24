import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleFoundationModelAvailability: Equatable, Sendable {
    case available
    case requiresIOS26
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable(String)

    var summary: String {
        switch self {
        case .available:
            return "Apple Intelligence is ready on this device"
        case .requiresIOS26:
            return "Requires iOS 26 or newer"
        case .deviceNotEligible:
            return "This device does not support Apple Intelligence"
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings"
        case .modelNotReady:
            return "The on-device model is still downloading or preparing"
        case .unavailable(let reason):
            return reason
        }
    }

    var isAvailable: Bool {
        self == .available
    }
}

enum PocketKernelAgentAction: String, Codable, CaseIterable, Sendable {
    case answer
    case shell
    case readFile
    case writeFile
    case listFiles
}

struct PocketKernelAgentPlan: Codable, Equatable, Sendable {
    var action: PocketKernelAgentAction
    var summary: String
    var response: String
    var command: String
    var workingDirectory: String
    var path: String
    var content: String
    var requiresNetwork: Bool
    var requiresApproval: Bool
    var isBlocked: Bool
    var riskExplanation: String

    static func answer(_ text: String) -> PocketKernelAgentPlan {
        PocketKernelAgentPlan(
            action: .answer,
            summary: "Answer locally",
            response: text,
            command: "",
            workingDirectory: "",
            path: "",
            content: "",
            requiresNetwork: false,
            requiresApproval: false,
            isBlocked: false,
            riskExplanation: ""
        )
    }
}

enum AppleFoundationModelProviderError: LocalizedError {
    case unavailable(AppleFoundationModelAvailability)
    case emptyRequest
    case invalidPlan(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let availability):
            return availability.summary
        case .emptyRequest:
            return "Enter a request first"
        case .invalidPlan(let reason):
            return reason
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable
private enum AppleGeneratedAction {
    case answer
    case shell
    case readFile
    case writeFile
    case listFiles
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable
private struct AppleGeneratedAgentPlan {
    @Guide(description: "The single action that best satisfies the request.")
    var action: AppleGeneratedAction

    @Guide(description: "A short, plain-language description of what will happen.")
    var summary: String

    @Guide(description: "The response to show the person. For tool actions, explain what the action will do before approval.")
    var response: String

    @Guide(description: "A POSIX shell command only when action is shell. Otherwise return an empty string.")
    var command: String

    @Guide(description: "The absolute Linux working directory. Use /root when the request does not provide one.")
    var workingDirectory: String

    @Guide(description: "The absolute file path for readFile, writeFile, or listFiles. Otherwise return an empty string.")
    var path: String

    @Guide(description: "Complete file contents only for writeFile. Otherwise return an empty string.")
    var content: String

    @Guide(description: "True only when the action genuinely requires internet access.")
    var requiresNetwork: Bool

    @Guide(description: "A concise explanation of material risk, or an empty string for ordinary low-risk actions.")
    var riskExplanation: String
}
#endif

actor AppleFoundationModelProvider {
    static let shared = AppleFoundationModelProvider()

    private static let instructions = """
    You are PocketKernel, a private on-device agent running on an iPhone.

    Convert the person's request into exactly one safe, minimal action. Prefer an answer when no local operation is necessary. Use file actions instead of shell when they are sufficient. Never claim that an action ran; you only prepare a proposal for explicit approval. Never include passwords, authentication tokens, private keys, destructive disk commands, privilege escalation, device-management commands, persistence mechanisms, or commands intended to bypass platform security. Do not use network access unless the request clearly requires current remote information.
    """

    nonisolated func availability() -> AppleFoundationModelAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .deviceNotEligible
                case .appleIntelligenceNotEnabled:
                    return .appleIntelligenceNotEnabled
                case .modelNotReady:
                    return .modelNotReady
                @unknown default:
                    return .unavailable("Apple's on-device model is unavailable")
                }
            }
        }
        #endif
        return .requiresIOS26
    }

    func respond(to rawRequest: String) async throws -> String {
        let request = try normalizedRequest(rawRequest)
        try requireAvailable()

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            let session = LanguageModelSession(instructions: Self.instructions)
            let result = try await session.respond(to: request)
            return result.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif

        throw AppleFoundationModelProviderError.unavailable(.requiresIOS26)
    }

    func plan(
        for rawRequest: String,
        conversationContext: String = "",
        workingDirectory: String = "/root"
    ) async throws -> PocketKernelAgentPlan {
        let request = try normalizedRequest(rawRequest)
        try requireAvailable()

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            let session = LanguageModelSession(instructions: Self.instructions)
            let prompt = """
            Current working directory: \(normalizedWorkingDirectory(workingDirectory))

            Relevant conversation context:
            \(conversationContext.trimmingCharacters(in: .whitespacesAndNewlines))

            Person's request:
            \(request)
            """
            let result = try await session.respond(
                to: prompt,
                generating: AppleGeneratedAgentPlan.self
            )
            return try validate(result.content)
        }
        #endif

        throw AppleFoundationModelProviderError.unavailable(.requiresIOS26)
    }

    private nonisolated func requireAvailable() throws {
        let status = availability()
        guard status.isAvailable else {
            throw AppleFoundationModelProviderError.unavailable(status)
        }
    }

    private nonisolated func normalizedRequest(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw AppleFoundationModelProviderError.emptyRequest
        }
        return value
    }

    private nonisolated func normalizedWorkingDirectory(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("/") ? value : "/root"
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macCatalyst 26.0, *)
    private nonisolated func validate(_ generated: AppleGeneratedAgentPlan) throws -> PocketKernelAgentPlan {
        let action: PocketKernelAgentAction
        switch generated.action {
        case .answer: action = .answer
        case .shell: action = .shell
        case .readFile: action = .readFile
        case .writeFile: action = .writeFile
        case .listFiles: action = .listFiles
        }

        let command = generated.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = generated.path.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = generated.response.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = generated.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let workingDirectory = normalizedWorkingDirectory(generated.workingDirectory)

        switch action {
        case .answer:
            guard !response.isEmpty else {
                throw AppleFoundationModelProviderError.invalidPlan("The on-device model returned an empty answer")
            }
        case .shell:
            guard !command.isEmpty else {
                throw AppleFoundationModelProviderError.invalidPlan("The on-device model proposed an empty command")
            }
        case .readFile, .writeFile, .listFiles:
            guard path.hasPrefix("/") else {
                throw AppleFoundationModelProviderError.invalidPlan("The on-device model must provide an absolute file path")
            }
        }

        let blockReason = blockedReason(action: action, command: command, path: path)
        let modelRisk = generated.riskExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
        let risk = blockReason ?? modelRisk

        return PocketKernelAgentPlan(
            action: action,
            summary: summary.isEmpty ? defaultSummary(for: action) : summary,
            response: response,
            command: action == .shell ? command : "",
            workingDirectory: workingDirectory,
            path: path,
            content: action == .writeFile ? generated.content : "",
            requiresNetwork: generated.requiresNetwork,
            requiresApproval: action != .answer,
            isBlocked: blockReason != nil,
            riskExplanation: risk
        )
    }
    #endif

    private nonisolated func defaultSummary(for action: PocketKernelAgentAction) -> String {
        switch action {
        case .answer: return "Answer locally"
        case .shell: return "Run a local command"
        case .readFile: return "Read a local file"
        case .writeFile: return "Write a local file"
        case .listFiles: return "List local files"
        }
    }

    private nonisolated func blockedReason(
        action: PocketKernelAgentAction,
        command: String,
        path: String
    ) -> String? {
        let lowered = command.lowercased()
        let blockedCommandFragments = [
            "rm -rf /",
            "mkfs",
            "dd if=",
            ":(){:|:&};:",
            "shutdown",
            "reboot",
            "launchctl",
            "sudo ",
            "su -",
            "/etc/shadow",
            "authorized_keys"
        ]

        if action == .shell,
           let fragment = blockedCommandFragments.first(where: { lowered.contains($0) }) {
            return "Blocked because the proposal contains a dangerous command pattern: \(fragment)"
        }

        let protectedPaths = ["/etc/shadow", "/etc/sudoers", "/root/.ssh/authorized_keys"]
        if action == .writeFile,
           protectedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return "Blocked because PocketKernel will not modify authentication or privilege files"
        }

        return nil
    }
}
