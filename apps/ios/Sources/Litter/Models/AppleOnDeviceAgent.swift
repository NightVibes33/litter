import Combine
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// A model-produced proposal. Nothing in this type executes automatically.
struct LocalAgentProposal: Codable, Equatable, Identifiable, Sendable {
    enum ActionKind: String, Codable, Sendable {
        case answer
        case runCommand
        case readFile
        case writeFile
        case listDirectory
    }

    enum Risk: String, Codable, Sendable {
        case low
        case medium
        case high
    }

    var id: UUID = UUID()
    var summary: String
    var explanation: String
    var action: ActionKind
    var command: String?
    var path: String?
    var content: String?
    var risk: Risk
    var requiresApproval: Bool

    private enum CodingKeys: String, CodingKey {
        case summary, explanation, action, command, path, content, risk, requiresApproval
    }
}

enum AppleOnDeviceAgentError: LocalizedError {
    case frameworkUnavailable
    case modelUnavailable(String)
    case invalidStructuredResponse
    case actionRejected(String)

    var errorDescription: String? {
        switch self {
        case .frameworkUnavailable:
            return "Apple Foundation Models is not available in this build."
        case .modelUnavailable(let reason):
            return "Apple's on-device model is unavailable: \(reason)"
        case .invalidStructuredResponse:
            return "The on-device model returned an invalid action proposal."
        case .actionRejected(let reason):
            return reason
        }
    }
}

actor AppleOnDeviceAgent {
    static let shared = AppleOnDeviceAgent()

    private let decoder = JSONDecoder()
    private let maxSummaryCharacters = 500
    private let maxExplanationCharacters = 4_000
    private let maxCommandCharacters = 8_000
    private let maxPathCharacters = 4_096
    private let maxWriteCharacters = 1_000_000

    var availabilityDescription: String {
        get async {
#if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                switch SystemLanguageModel.default.availability {
                case .available:
                    return "Available"
                case .unavailable(let reason):
                    return "Unavailable: \(String(describing: reason))"
                }
            }
#endif
            return "Foundation Models framework unavailable"
        }
    }

    func propose(userRequest: String, context: String = "") async throws -> LocalAgentProposal {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw AppleOnDeviceAgentError.modelUnavailable(String(describing: model.availability))
            }

            let instructions = """
            You are PocketKernel, a privacy-first local agent running entirely on this Apple device.
            Convert the user's request into exactly one JSON object and no markdown.

            Required JSON keys:
            summary, explanation, action, command, path, content, risk, requiresApproval

            action must be one of: answer, runCommand, readFile, writeFile, listDirectory.
            risk must be one of: low, medium, high.
            Use null for command, path, or content when not applicable.
            Every action other than answer must set requiresApproval to true.
            Never invent that an action already ran. Only propose it.
            Prefer a plain answer when execution is unnecessary.
            """

            let session = LanguageModelSession(model: model, instructions: instructions)
            let prompt = """
            User request:
            \(userRequest)

            Local context:
            \(context.isEmpty ? "No additional context." : context)
            """
            let response = try await session.respond(to: prompt)
            return try decodeAndValidate(response.content)
        }
#endif
        throw AppleOnDeviceAgentError.frameworkUnavailable
    }

    private func decodeAndValidate(_ raw: String) throws -> LocalAgentProposal {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              var proposal = try? decoder.decode(LocalAgentProposal.self, from: data) else {
            throw AppleOnDeviceAgentError.invalidStructuredResponse
        }

        proposal.id = UUID()
        proposal.summary = proposal.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        proposal.explanation = proposal.explanation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !proposal.summary.isEmpty,
              proposal.summary.count <= maxSummaryCharacters,
              proposal.explanation.count <= maxExplanationCharacters else {
            throw AppleOnDeviceAgentError.invalidStructuredResponse
        }

        switch proposal.action {
        case .answer:
            proposal.command = nil
            proposal.path = nil
            proposal.content = nil
            proposal.requiresApproval = false

        case .runCommand:
            guard let command = proposal.command?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !command.isEmpty,
                  command.count <= maxCommandCharacters else {
                throw AppleOnDeviceAgentError.invalidStructuredResponse
            }
            guard !command.contains("\0") else {
                throw AppleOnDeviceAgentError.actionRejected("The proposed command contains invalid data.")
            }
            proposal.command = command
            proposal.path = nil
            proposal.content = nil
            proposal.requiresApproval = true

        case .readFile, .writeFile, .listDirectory:
            guard let path = proposal.path?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty,
                  path.count <= maxPathCharacters else {
                throw AppleOnDeviceAgentError.invalidStructuredResponse
            }
            guard !path.contains("\0"),
                  path.rangeOfCharacter(from: .controlCharacters) == nil else {
                throw AppleOnDeviceAgentError.actionRejected("The proposed path contains invalid data.")
            }

            proposal.path = path
            proposal.command = nil
            proposal.requiresApproval = true

            if proposal.action == .writeFile {
                guard let content = proposal.content,
                      content.count <= maxWriteCharacters else {
                    throw AppleOnDeviceAgentError.actionRejected("The proposed file content is missing or too large.")
                }
                proposal.content = content
            } else {
                proposal.content = nil
            }
        }

        return proposal
    }
}

/// Central approval gate between model output and Litter's existing local runtime.
@MainActor
final class LocalActionApprovalCoordinator: ObservableObject {
    @Published private(set) var pendingProposal: LocalAgentProposal?
    @Published private(set) var isExecuting = false
    @Published private(set) var lastError: String?

    func present(_ proposal: LocalAgentProposal) {
        pendingProposal = proposal
        lastError = nil
    }

    func reject() {
        pendingProposal = nil
        isExecuting = false
        lastError = nil
    }

    /// The caller supplies Litter/litter-ish execution. This coordinator never bypasses approval.
    func approve<Result: Sendable>(
        execute: @escaping @Sendable (LocalAgentProposal) async throws -> Result
    ) async -> Result? {
        guard let proposal = pendingProposal else { return nil }
        guard proposal.requiresApproval else {
            pendingProposal = nil
            return nil
        }

        isExecuting = true
        lastError = nil
        defer { isExecuting = false }

        do {
            let result = try await execute(proposal)
            pendingProposal = nil
            return result
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
