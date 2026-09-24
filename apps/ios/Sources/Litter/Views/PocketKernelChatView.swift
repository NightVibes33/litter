import SwiftUI

private struct PocketKernelChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
        case execution
        case error
    }

    let id: UUID
    let role: Role
    let text: String

    init(role: Role, text: String) {
        self.id = UUID()
        self.role = role
        self.text = text
    }
}

struct PocketKernelChatView: View {
    @State private var agent = PocketKernelLocalAgent.shared
    @State private var messages: [PocketKernelChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var allowNetwork = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            Divider().overlay(LitterTheme.textMuted.opacity(0.2))
            transcript
        }
        .background(AlleyBackdrop().ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .navigationTitle("PocketKernel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    messages.removeAll()
                    agent.reset()
                    draft = ""
                    allowNetwork = false
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Reset chat")
            }
        }
        .task {
            if messages.isEmpty {
                messages.append(
                    PocketKernelChatMessage(
                        role: .assistant,
                        text: welcomeText
                    )
                )
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LitterTheme.accent.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LitterTheme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Apple On-Device")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LitterTheme.textPrimary)
                Text(agent.modelAvailability.summary)
                    .font(.caption)
                    .foregroundStyle(
                        agent.modelAvailability.isAvailable
                            ? LitterTheme.accent
                            : LitterTheme.warning
                    )
                    .lineLimit(2)
            }

            Spacer()

            Label("Private", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LitterTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(LitterTheme.surface.opacity(0.78), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if case .awaitingApproval(let plan) = agent.phase {
                        approvalCard(plan)
                            .id("pending-approval")
                    }

                    if isSending || isExecuting {
                        progressRow
                            .id("agent-progress")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: agent.phase) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: PocketKernelChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 44)
            }

            VStack(alignment: .leading, spacing: 6) {
                if message.role != .user {
                    Label(messageLabel(message.role), systemImage: messageIcon(message.role))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(messageAccent(message.role))
                }

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(LitterTheme.textPrimary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(messageBackground(message.role), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(messageAccent(message.role).opacity(0.2), lineWidth: 0.8)
            }

            if message.role != .user {
                Spacer(minLength: 28)
            }
        }
    }

    private func approvalCard(_ plan: PocketKernelAgentPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: plan.isBlocked ? "hand.raised.fill" : "checkmark.shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(plan.isBlocked ? LitterTheme.danger : LitterTheme.warning)

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.isBlocked ? "Action blocked" : "Approval required")
                        .font(.headline)
                        .foregroundStyle(LitterTheme.textPrimary)
                    Text(plan.summary)
                        .font(.subheadline)
                        .foregroundStyle(LitterTheme.textSecondary)
                }
            }

            if !plan.response.isEmpty {
                Text(plan.response)
                    .font(.subheadline)
                    .foregroundStyle(LitterTheme.textSecondary)
            }

            planDetails(plan)

            if !plan.riskExplanation.isEmpty {
                Label(plan.riskExplanation, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(plan.isBlocked ? LitterTheme.danger : LitterTheme.warning)
            }

            if plan.requiresNetwork && !plan.isBlocked {
                Toggle(isOn: $allowNetwork) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow network for this run")
                            .font(.subheadline.weight(.semibold))
                        Text("This approval applies only to the proposed action.")
                            .font(.caption)
                            .foregroundStyle(LitterTheme.textMuted)
                    }
                }
                .tint(LitterTheme.accent)
            }

            HStack(spacing: 10) {
                Button("Reject", role: .destructive) {
                    agent.rejectPendingPlan()
                    allowNetwork = false
                    messages.append(.init(role: .assistant, text: "Action rejected. Nothing was run."))
                }
                .buttonStyle(.bordered)

                Spacer()

                if !plan.isBlocked {
                    Button {
                        Task { await approve(plan) }
                    } label: {
                        Label("Approve and run", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LitterTheme.accent)
                    .disabled(plan.requiresNetwork && !allowNetwork)
                }
            }
        }
        .padding(16)
        .background(LitterTheme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke((plan.isBlocked ? LitterTheme.danger : LitterTheme.warning).opacity(0.36), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func planDetails(_ plan: PocketKernelAgentPlan) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            detailRow("Action", value: plan.action.rawValue)

            if plan.action == .shell {
                detailCode("Command", value: plan.command)
                detailRow("Working directory", value: plan.workingDirectory)
            }

            if [.readFile, .writeFile, .listFiles].contains(plan.action) {
                detailCode("Path", value: plan.path)
            }

            if plan.action == .writeFile {
                detailCode("New contents", value: plan.content)
            }

            detailRow("Network", value: plan.requiresNetwork ? "Requested" : "Not requested")
        }
        .padding(12)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LitterTheme.textMuted)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(LitterTheme.textPrimary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func detailCode(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LitterTheme.textMuted)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(LitterTheme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progressRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(LitterTheme.accent)
            Text(isExecuting ? "Running locally…" : "Thinking on device…")
                .font(.subheadline)
                .foregroundStyle(LitterTheme.textSecondary)
            Spacer()
        }
        .padding(14)
        .background(LitterTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var composer: some View {
        VStack(spacing: 8) {
            Divider().overlay(LitterTheme.textMuted.opacity(0.16))

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask PocketKernel…", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(LitterTheme.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(LitterTheme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        agent.modelAvailability.isAvailable
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending
            && !isExecuting
            && agent.pendingPlan == nil
    }

    private var isExecuting: Bool {
        if case .executing = agent.phase { return true }
        return false
    }

    private var welcomeText: String {
        "I use Apple’s on-device model to answer privately and prepare local actions. Commands and file changes are shown for approval before the iSH runtime executes anything."
    }

    private func send() async {
        let request = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }

        draft = ""
        composerFocused = false
        allowNetwork = false
        isSending = true
        messages.append(.init(role: .user, text: request))

        do {
            let context = messages.suffix(10).map { message in
                "\(messageLabel(message.role)): \(message.text)"
            }.joined(separator: "\n")

            let plan = try await agent.prepare(
                request: request,
                conversationContext: context,
                workingDirectory: "/root"
            )

            if plan.action == .answer {
                messages.append(.init(role: .assistant, text: plan.response))
            }
        } catch {
            messages.append(.init(role: .error, text: error.localizedDescription))
        }

        isSending = false
    }

    private func approve(_ plan: PocketKernelAgentPlan) async {
        do {
            let result = try await agent.approvePendingPlan(allowNetwork: allowNetwork)
            let output = result.output.isEmpty
                ? "Completed with exit code \(result.exitCode)."
                : result.output
            messages.append(.init(role: .execution, text: output))
            allowNetwork = false
        } catch {
            messages.append(.init(role: .error, text: error.localizedDescription))
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            if agent.pendingPlan != nil {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("pending-approval", anchor: .bottom)
                }
            } else if let id = messages.last?.id {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private func messageLabel(_ role: PocketKernelChatMessage.Role) -> String {
        switch role {
        case .user: return "You"
        case .assistant: return "PocketKernel"
        case .execution: return "Local runtime"
        case .error: return "Error"
        }
    }

    private func messageIcon(_ role: PocketKernelChatMessage.Role) -> String {
        switch role {
        case .user: return "person.fill"
        case .assistant: return "apple.intelligence"
        case .execution: return "terminal.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private func messageAccent(_ role: PocketKernelChatMessage.Role) -> Color {
        switch role {
        case .user, .assistant: return LitterTheme.accent
        case .execution: return .green
        case .error: return LitterTheme.danger
        }
    }

    private func messageBackground(_ role: PocketKernelChatMessage.Role) -> Color {
        switch role {
        case .user: return LitterTheme.accent.opacity(0.16)
        case .assistant, .execution, .error: return LitterTheme.surface.opacity(0.84)
        }
    }
}
