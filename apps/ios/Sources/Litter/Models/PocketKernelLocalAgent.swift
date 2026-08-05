import Foundation
import Observation

struct PocketKernelExecutionResult: Equatable, Sendable {
    var action: PocketKernelAgentAction
    var output: String
    var exitCode: Int32
    var duration: TimeInterval
}

enum PocketKernelLocalAgentError: LocalizedError {
    case noPendingPlan
    case approvalRequired
    case networkApprovalRequired
    case blocked(String)
    case terminalFailed(String)
    case terminalTimeout
    case invalidAction(String)

    var errorDescription: String? {
        switch self {
        case .noPendingPlan:
            return "There is no pending action to run"
        case .approvalRequired:
            return "Approve the proposed action before it runs"
        case .networkApprovalRequired:
            return "This action also needs explicit network approval"
        case .blocked(let reason):
            return reason
        case .terminalFailed(let reason):
            return reason
        case .terminalTimeout:
            return "The local command timed out"
        case .invalidAction(let reason):
            return reason
        }
    }
}

@MainActor
@Observable
final class PocketKernelLocalAgent {
    static let shared = PocketKernelLocalAgent()

    enum Phase: Equatable {
        case idle
        case planning
        case awaitingApproval(PocketKernelAgentPlan)
        case executing(PocketKernelAgentPlan)
        case completed(PocketKernelExecutionResult)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var pendingPlan: PocketKernelAgentPlan?
    private(set) var lastResult: PocketKernelExecutionResult?

    @ObservationIgnored private let modelProvider: AppleFoundationModelProvider
    @ObservationIgnored private let terminal: TerminalSessionController
    @ObservationIgnored private var activeTask: Task<Void, Never>?

    init(
        modelProvider: AppleFoundationModelProvider = .shared,
        terminal: TerminalSessionController = TerminalSessionController()
    ) {
        self.modelProvider = modelProvider
        self.terminal = terminal
    }

    var modelAvailability: AppleFoundationModelAvailability {
        modelProvider.availability()
    }

    func prepare(
        request: String,
        conversationContext: String = "",
        workingDirectory: String = "/root"
    ) async throws -> PocketKernelAgentPlan {
        cancelActiveWork(resetPhase: false)
        phase = .planning

        do {
            let plan = try await modelProvider.plan(
                for: request,
                conversationContext: conversationContext,
                workingDirectory: workingDirectory
            )
            pendingPlan = plan.requiresApproval ? plan : nil

            if plan.requiresApproval {
                phase = .awaitingApproval(plan)
            } else {
                let result = PocketKernelExecutionResult(
                    action: .answer,
                    output: plan.response,
                    exitCode: 0,
                    duration: 0
                )
                lastResult = result
                phase = .completed(result)
            }
            return plan
        } catch {
            pendingPlan = nil
            phase = .failed(error.localizedDescription)
            throw error
        }
    }

    func approvePendingPlan(allowNetwork: Bool = false) async throws -> PocketKernelExecutionResult {
        guard let plan = pendingPlan else {
            throw PocketKernelLocalAgentError.noPendingPlan
        }
        guard plan.requiresApproval else {
            throw PocketKernelLocalAgentError.approvalRequired
        }
        if plan.requiresNetwork && !allowNetwork {
            throw PocketKernelLocalAgentError.networkApprovalRequired
        }
        if plan.isBlocked {
            throw PocketKernelLocalAgentError.blocked(
                plan.riskExplanation.isEmpty ? "PocketKernel blocked this action" : plan.riskExplanation
            )
        }

        phase = .executing(plan)
        let startedAt = Date()

        do {
            let shellCommand = try command(for: plan)
            let result = try await executeShell(
                shellCommand,
                workingDirectory: plan.workingDirectory,
                action: plan.action,
                startedAt: startedAt
            )
            pendingPlan = nil
            lastResult = result
            phase = .completed(result)
            return result
        } catch {
            phase = .failed(error.localizedDescription)
            throw error
        }
    }

    func rejectPendingPlan() {
        pendingPlan = nil
        phase = .idle
    }

    func reset() {
        cancelActiveWork(resetPhase: true)
        pendingPlan = nil
        lastResult = nil
        terminal.close()
    }

    func cancel() {
        cancelActiveWork(resetPhase: true)
        terminal.close()
    }

    private func cancelActiveWork(resetPhase: Bool) {
        activeTask?.cancel()
        activeTask = nil
        if resetPhase {
            phase = .idle
        }
    }

    private func command(for plan: PocketKernelAgentPlan) throws -> String {
        switch plan.action {
        case .answer:
            throw PocketKernelLocalAgentError.invalidAction("Answers do not require execution")
        case .shell:
            let command = plan.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else {
                throw PocketKernelLocalAgentError.invalidAction("The proposed shell command is empty")
            }
            return command
        case .readFile:
            return "cat -- \(shellQuote(plan.path))"
        case .listFiles:
            return "ls -la -- \(shellQuote(plan.path))"
        case .writeFile:
            let encoded = Data(plan.content.utf8).base64EncodedString()
            let quotedPath = shellQuote(plan.path)
            let quotedPayload = shellQuote(encoded)
            return "mkdir -p -- \"$(dirname -- \(quotedPath))\" && printf '%s' \(quotedPayload) | base64 -d > \(quotedPath)"
        }
    }

    private func executeShell(
        _ command: String,
        workingDirectory: String,
        action: PocketKernelAgentAction,
        startedAt: Date
    ) async throws -> PocketKernelExecutionResult {
        if terminal.sessionId == nil {
            await terminal.openLocalIsh(cwd: workingDirectory)
        }

        try await waitForTerminalReady()
        terminal.clearOutput()

        let marker = "__POCKETKERNEL_EXIT_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))__"
        let directory = workingDirectory.hasPrefix("/") ? workingDirectory : "/root"
        let wrapped = "cd \(shellQuote(directory)) && { \(command)\n}; __pk_status=$?; printf '\\n\(marker)%s\\n' \"$__pk_status\""
        await terminal.sendLine(wrapped)

        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            try Task.checkCancellation()

            if let parsed = parseCompletedOutput(terminal.output, marker: marker) {
                return PocketKernelExecutionResult(
                    action: action,
                    output: parsed.output,
                    exitCode: parsed.exitCode,
                    duration: Date().timeIntervalSince(startedAt)
                )
            }

            switch terminal.phase {
            case .failed(let reason):
                throw PocketKernelLocalAgentError.terminalFailed(reason)
            case .exited(let code):
                throw PocketKernelLocalAgentError.terminalFailed(
                    "The local shell exited before reporting completion (\(code))"
                )
            case .idle, .connecting, .running:
                break
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        throw PocketKernelLocalAgentError.terminalTimeout
    }

    private func waitForTerminalReady() async throws {
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            switch terminal.phase {
            case .running:
                return
            case .failed(let reason):
                throw PocketKernelLocalAgentError.terminalFailed(reason)
            case .exited(let code):
                throw PocketKernelLocalAgentError.terminalFailed(
                    "The local shell exited while opening (\(code))"
                )
            case .idle, .connecting:
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        throw PocketKernelLocalAgentError.terminalFailed("The local iSH runtime did not become ready")
    }

    private func parseCompletedOutput(
        _ rawOutput: String,
        marker: String
    ) -> (output: String, exitCode: Int32)? {
        guard let markerRange = rawOutput.range(of: marker, options: .backwards) else {
            return nil
        }

        let statusText = rawOutput[markerRange.upperBound...]
            .prefix { $0.isNumber || $0 == "-" }
        guard let exitCode = Int32(String(statusText)) else {
            return nil
        }

        var output = String(rawOutput[..<markerRange.lowerBound])
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return (output, exitCode)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
