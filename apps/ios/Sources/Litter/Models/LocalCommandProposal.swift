import Foundation

enum LocalActionRisk: String, Codable, CaseIterable, Sendable {
    case readOnly
    case modifiesFiles
    case network
    case destructive

    var displayName: String {
        switch self {
        case .readOnly: return "Read only"
        case .modifiesFiles: return "Changes files"
        case .network: return "Uses network"
        case .destructive: return "Destructive"
        }
    }
}

enum LocalActionApprovalState: String, Codable, Sendable {
    case proposed
    case approved
    case rejected
    case running
    case succeeded
    case failed
}

struct LocalCommandProposal: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let command: String
    let workingDirectory: String
    let rationale: String
    let requiresNetwork: Bool
    let risk: LocalActionRisk
    private(set) var approvalState: LocalActionApprovalState
    let createdAt: Date
    private(set) var updatedAt: Date

    init(
        id: UUID = UUID(),
        command: String,
        workingDirectory: String = "~",
        rationale: String,
        requiresNetwork: Bool = false,
        risk: LocalActionRisk = .readOnly,
        approvalState: LocalActionApprovalState = .proposed,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        self.workingDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rationale = rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        self.requiresNetwork = requiresNetwork
        self.risk = risk
        self.approvalState = approvalState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var canExecute: Bool {
        approvalState == .approved && !command.isEmpty
    }

    mutating func transition(to next: LocalActionApprovalState) throws {
        guard Self.allowedTransitions[approvalState, default: []].contains(next) else {
            throw LocalActionApprovalError.invalidTransition(from: approvalState, to: next)
        }
        approvalState = next
        updatedAt = Date()
    }

    private static let allowedTransitions: [LocalActionApprovalState: Set<LocalActionApprovalState>] = [
        .proposed: [.approved, .rejected],
        .approved: [.running, .rejected],
        .running: [.succeeded, .failed],
        .rejected: [],
        .succeeded: [],
        .failed: []
    ]
}

enum LocalActionApprovalError: LocalizedError, Equatable {
    case unknownProposal(UUID)
    case emptyCommand
    case invalidTransition(from: LocalActionApprovalState, to: LocalActionApprovalState)
    case executionNotApproved(LocalActionApprovalState)

    var errorDescription: String? {
        switch self {
        case .unknownProposal:
            return "The proposed action no longer exists."
        case .emptyCommand:
            return "The proposed command is empty."
        case .invalidTransition(let current, let next):
            return "Cannot move an action from \(current.rawValue) to \(next.rawValue)."
        case .executionNotApproved(let state):
            return "The action is \(state.rawValue), not approved."
        }
    }
}

/// A central approval boundary between the model and the local Linux runtime.
///
/// The model may register a proposal, but only a user-driven `approve` call can
/// make it claimable for execution. Runtime adapters must call
/// `claimForExecution` instead of running model output directly.
actor LocalActionApprovalGate {
    static let shared = LocalActionApprovalGate()

    private var proposals: [UUID: LocalCommandProposal] = [:]

    @discardableResult
    func register(_ proposal: LocalCommandProposal) throws -> LocalCommandProposal {
        guard !proposal.command.isEmpty else {
            throw LocalActionApprovalError.emptyCommand
        }
        proposals[proposal.id] = proposal
        return proposal
    }

    func proposal(id: UUID) -> LocalCommandProposal? {
        proposals[id]
    }

    func pendingProposals() -> [LocalCommandProposal] {
        proposals.values
            .filter { $0.approvalState == .proposed || $0.approvalState == .approved }
            .sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func approve(id: UUID) throws -> LocalCommandProposal {
        try transition(id: id, to: .approved)
    }

    @discardableResult
    func reject(id: UUID) throws -> LocalCommandProposal {
        try transition(id: id, to: .rejected)
    }

    @discardableResult
    func claimForExecution(id: UUID) throws -> LocalCommandProposal {
        guard var proposal = proposals[id] else {
            throw LocalActionApprovalError.unknownProposal(id)
        }
        guard proposal.canExecute else {
            throw LocalActionApprovalError.executionNotApproved(proposal.approvalState)
        }
        try proposal.transition(to: .running)
        proposals[id] = proposal
        return proposal
    }

    @discardableResult
    func complete(id: UUID, succeeded: Bool) throws -> LocalCommandProposal {
        try transition(id: id, to: succeeded ? .succeeded : .failed)
    }

    func remove(id: UUID) {
        proposals[id] = nil
    }

    private func transition(
        id: UUID,
        to state: LocalActionApprovalState
    ) throws -> LocalCommandProposal {
        guard var proposal = proposals[id] else {
            throw LocalActionApprovalError.unknownProposal(id)
        }
        try proposal.transition(to: state)
        proposals[id] = proposal
        return proposal
    }
}
