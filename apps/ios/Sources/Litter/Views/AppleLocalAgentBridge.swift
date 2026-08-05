import Foundation
import SwiftUI

@MainActor
final class AppleLocalAgentBridge: ObservableObject {
    enum Phase: Equatable {
        case idle
        case proposing
        case awaitingApproval
        case executing
        case completed
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var request = ""
    @Published private(set) var proposal: LocalAgentProposal?
    @Published private(set) var output: String?
    @Published private(set) var errorMessage: String?

    let approval = LocalActionApprovalCoordinator()

    var isBusy: Bool {
        phase == .proposing || phase == .executing
    }

    func submit(request rawRequest: String, context: String) async {
        let trimmed = rawRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fail("Enter a request before sending it to the on-device model.")
            return
        }

        approval.reject()
        request = trimmed
        proposal = nil
        output = nil
        errorMessage = nil
        phase = .proposing

        do {
            let next = try await AppleOnDeviceAgent.shared.propose(
                userRequest: trimmed,
                context: context
            )
            proposal = next

            if next.action == .answer {
                output = Self.answerText(for: next)
                phase = .completed
            } else {
                approval.present(next)
                phase = .awaitingApproval
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    func approve(workDirectory: String) async {
        guard phase == .awaitingApproval else { return }
        phase = .executing
        errorMessage = nil

        let normalizedWorkDirectory = Self.normalizedWorkDirectory(workDirectory)
        let result: String? = await approval.approve { proposal in
            try await Self.execute(
                proposal,
                workDirectory: normalizedWorkDirectory
            )
        }

        if let result {
            output = result
            phase = .completed
        } else {
            fail(approval.lastError ?? "The approved action could not be completed.")
        }
    }

    func reject() {
        approval.reject()
        output = "Action rejected. Nothing was executed."
        errorMessage = nil
        phase = .completed
    }

    func reset() {
        approval.reject()
        request = ""
        proposal = nil
        output = nil
        errorMessage = nil
        phase = .idle
    }

    private func fail(_ message: String) {
        errorMessage = message
        phase = .failed
    }

    nonisolated private static func execute(
        _ proposal: LocalAgentProposal,
        workDirectory: String
    ) async throws -> String {
        switch proposal.action {
        case .answer:
            return answerText(for: proposal)

        case .runCommand:
            guard let command = proposal.command else {
                throw bridgeError("The approved command is missing.")
            }
            let result = await IshFS.run(command, cwd: workDirectory)
            guard result.exitCode == 0 else {
                throw runtimeError(
                    label: "Command",
                    exitCode: result.exitCode,
                    output: result.output
                )
            }
            let body = result.output.isEmpty ? "(no output)" : limited(result.output)
            return "$ \(command)\n\n\(body)"

        case .readFile:
            guard let rawPath = proposal.path else {
                throw bridgeError("The approved file path is missing.")
            }
            let path = resolvedPath(rawPath, workDirectory: workDirectory)
            let text = try await IshFS.readTextFile(path: path, maxBytes: 256_000)
            return "\(path)\n\n\(limited(text))"

        case .writeFile:
            guard let rawPath = proposal.path,
                  let content = proposal.content else {
                throw bridgeError("The approved file write is incomplete.")
            }
            let path = resolvedPath(rawPath, workDirectory: workDirectory)
            try await IshFS.writeTextFile(path: path, text: content)
            return "Wrote \(content.utf8.count) bytes to \(path)."

        case .listDirectory:
            guard let rawPath = proposal.path else {
                throw bridgeError("The approved directory path is missing.")
            }
            let path = resolvedPath(rawPath, workDirectory: workDirectory)
            let command = "LC_ALL=C ls -la -- \(IshFS.shellQuote(path))"
            let result = await IshFS.run(command, cwd: workDirectory)
            guard result.exitCode == 0 else {
                throw runtimeError(
                    label: "Directory listing",
                    exitCode: result.exitCode,
                    output: result.output
                )
            }
            let body = result.output.isEmpty ? "(empty directory)" : limited(result.output)
            return "\(path)\n\n\(body)"
        }
    }

    nonisolated private static func answerText(for proposal: LocalAgentProposal) -> String {
        let summary = proposal.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let explanation = proposal.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        if explanation.isEmpty || explanation == summary {
            return summary
        }
        return "\(summary)\n\n\(explanation)"
    }

    nonisolated private static func normalizedWorkDirectory(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "/root"
        let candidate = trimmed.isEmpty ? fallback : trimmed
        return (candidate as NSString).standardizingPath
    }

    nonisolated private static func resolvedPath(
        _ value: String,
        workDirectory: String
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return (trimmed as NSString).standardizingPath
        }
        let combined = (workDirectory as NSString).appendingPathComponent(trimmed)
        return (combined as NSString).standardizingPath
    }

    nonisolated private static func limited(_ value: String) -> String {
        let limit = 64_000
        guard value.count > limit else { return value }
        return "… output truncated …\n" + String(value.suffix(limit))
    }

    nonisolated private static func bridgeError(_ message: String) -> NSError {
        NSError(
            domain: "AppleLocalAgentBridge",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    nonisolated private static func runtimeError(
        label: String,
        exitCode: Int32,
        output: String
    ) -> NSError {
        let details = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = details.isEmpty
            ? "\(label) failed with exit code \(exitCode)."
            : "\(label) failed with exit code \(exitCode).\n\n\(limited(details))"
        return NSError(
            domain: "AppleLocalAgentBridge",
            code: Int(exitCode),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

struct AppleLocalAgentBridgeSheet: View {
    @ObservedObject var bridge: AppleLocalAgentBridge
    let workDirectory: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusHeader
                    requestCard

                    if bridge.phase == .proposing || bridge.phase == .executing {
                        progressCard
                    }

                    if let proposal = bridge.proposal {
                        proposalCard(proposal)
                    }

                    if let errorMessage = bridge.errorMessage {
                        messageCard(
                            title: "Error",
                            systemImage: "exclamationmark.triangle.fill",
                            text: errorMessage,
                            tint: LitterTheme.danger,
                            monospaced: false
                        )
                    }

                    if let output = bridge.output {
                        messageCard(
                            title: bridge.proposal?.action == .answer ? "Response" : "Result",
                            systemImage: bridge.proposal?.action == .answer ? "apple.intelligence" : "checkmark.circle.fill",
                            text: output,
                            tint: LitterTheme.success,
                            monospaced: bridge.proposal?.action != .answer
                        )
                    }
                }
                .padding(16)
            }
            .background(AlleyBackdrop().ignoresSafeArea())
            .navigationTitle("Apple On-Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .disabled(bridge.phase == .executing)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if bridge.phase == .awaitingApproval {
                    approvalBar
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(bridge.phase == .executing)
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LitterTheme.accent.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: phaseIcon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(phaseTint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(phaseTitle)
                    .litterFont(.headline)
                    .foregroundColor(LitterTheme.textPrimary)
                Text("Runs privately with Apple's system model")
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textSecondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var requestCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Request", systemImage: "text.bubble")
                .litterFont(.caption, weight: .semibold)
                .foregroundColor(LitterTheme.textSecondary)
            Text(bridge.request.isEmpty ? "Preparing request…" : bridge.request)
                .litterFont(.body)
                .foregroundColor(LitterTheme.textPrimary)
                .textSelection(.enabled)
        }
        .cardStyle()
    }

    private var progressCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(LitterTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(bridge.phase == .proposing ? "Thinking on device" : "Running approved action")
                    .litterFont(.subheadline, weight: .semibold)
                    .foregroundColor(LitterTheme.textPrimary)
                Text(bridge.phase == .proposing ? "No prompt is being sent to a server." : "Using Litter's existing local iSH runtime.")
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textSecondary)
            }
        }
        .cardStyle()
    }

    private func proposalCard(_ proposal: LocalAgentProposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(proposal.action.displayName, systemImage: proposal.action.systemImage)
                    .litterFont(.caption, weight: .bold)
                    .foregroundColor(LitterTheme.accent)
                Spacer(minLength: 0)
                Text(proposal.risk.rawValue.uppercased())
                    .litterFont(.caption2, weight: .bold)
                    .foregroundColor(riskTint(proposal.risk))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(riskTint(proposal.risk).opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(proposal.summary)
                .litterFont(.headline)
                .foregroundColor(LitterTheme.textPrimary)

            if !proposal.explanation.isEmpty {
                Text(proposal.explanation)
                    .litterFont(.body)
                    .foregroundColor(LitterTheme.textBody)
                    .textSelection(.enabled)
            }

            if let command = proposal.command {
                detailBlock(title: "COMMAND", text: command)
            }

            if let path = proposal.path {
                detailBlock(title: "PATH", text: path)
            }

            if let content = proposal.content {
                detailBlock(title: "CONTENT", text: content)
            }

            if proposal.requiresApproval && bridge.phase == .awaitingApproval {
                Label("Nothing runs until you approve this exact action.", systemImage: "hand.raised.fill")
                    .litterFont(.caption, weight: .semibold)
                    .foregroundColor(LitterTheme.warning)
            }
        }
        .cardStyle()
    }

    private func detailBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .litterFont(.caption2, weight: .bold)
                .foregroundColor(LitterTheme.textMuted)
            ScrollView(.horizontal, showsIndicators: true) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(LitterTheme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(LitterTheme.codeBackground.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func messageCard(
        title: String,
        systemImage: String,
        text: String,
        tint: Color,
        monospaced: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .litterFont(.caption, weight: .bold)
                .foregroundColor(tint)
            Text(text)
                .font(monospaced ? .system(size: 12, design: .monospaced) : LitterFont.styled(size: 16))
                .foregroundColor(LitterTheme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
    }

    private var approvalBar: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                bridge.reject()
            } label: {
                Text("Reject")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                Task { await bridge.approve(workDirectory: workDirectory) }
            } label: {
                Label("Approve & Run", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(LitterTheme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
    }

    private var phaseTitle: String {
        switch bridge.phase {
        case .idle: return "Ready"
        case .proposing: return "Creating proposal"
        case .awaitingApproval: return "Approval required"
        case .executing: return "Executing locally"
        case .completed: return "Complete"
        case .failed: return "Could not complete"
        }
    }

    private var phaseIcon: String {
        switch bridge.phase {
        case .idle: return "apple.intelligence"
        case .proposing: return "sparkles"
        case .awaitingApproval: return "hand.raised.fill"
        case .executing: return "terminal.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private var phaseTint: Color {
        switch bridge.phase {
        case .failed: return LitterTheme.danger
        case .awaitingApproval: return LitterTheme.warning
        case .completed: return LitterTheme.success
        default: return LitterTheme.accent
        }
    }

    private func riskTint(_ risk: LocalAgentProposal.Risk) -> Color {
        switch risk {
        case .low: return LitterTheme.success
        case .medium: return LitterTheme.warning
        case .high: return LitterTheme.danger
        }
    }
}

private extension LocalAgentProposal.ActionKind {
    var displayName: String {
        switch self {
        case .answer: return "Answer"
        case .runCommand: return "Run Command"
        case .readFile: return "Read File"
        case .writeFile: return "Write File"
        case .listDirectory: return "List Directory"
        }
    }

    var systemImage: String {
        switch self {
        case .answer: return "text.bubble.fill"
        case .runCommand: return "terminal.fill"
        case .readFile: return "doc.text.fill"
        case .writeFile: return "square.and.pencil"
        case .listDirectory: return "folder.fill"
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LitterTheme.surface.opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(LitterTheme.border, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
