import SwiftUI

struct AppleIntelligenceChatView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AppleIntelligenceChatStore.shared
    @State private var draft = ""
    @State private var didSendInitialPrompt = false
    @FocusState private var composerFocused: Bool

    let initialPrompt: String?

    init(initialPrompt: String? = nil) {
        self.initialPrompt = initialPrompt
    }

    var body: some View {
        ZStack {
            AlleyBackdrop().ignoresSafeArea()

            VStack(spacing: 0) {
                statusHeader
                Divider().overlay(LitterTheme.textMuted.opacity(0.18))
                transcript
                composer
            }
        }
        .navigationTitle("PocketKernel Local")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        store.clear()
                    } label: {
                        Label("Clear Local Chat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await store.refreshStatus()
            await sendInitialPromptIfNeeded()
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                Image(systemName: statusSymbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Apple Intelligence")
                    .litterFont(.subheadline, weight: .bold)
                    .foregroundStyle(LitterTheme.textPrimary)
                Text(store.runtimeStatus.summary)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Label("On device", systemImage: "iphone")
                .litterFont(.caption, weight: .semibold)
                .foregroundStyle(LitterTheme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(LitterTheme.accent.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if store.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.messages) { message in
                            localMessageBubble(message)
                                .id(message.id)
                        }
                    }

                    if store.isResponding {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(LitterTheme.accent)
                            Text("Thinking on this device…")
                                .litterFont(.caption)
                                .foregroundStyle(LitterTheme.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .id("local-thinking")
                    }

                    if let error = store.errorMessage {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(LitterTheme.warning)
                            Text(error)
                                .litterFont(.caption)
                                .foregroundStyle(LitterTheme.textSecondary)
                            Spacer()
                        }
                        .padding(12)
                        .background(LitterTheme.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                    }

                    Color.clear.frame(height: 1).id("local-bottom")
                }
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.count) { _, _ in
                withAnimation(.snappy) {
                    proxy.scrollTo("local-bottom", anchor: .bottom)
                }
            }
            .onChange(of: store.isResponding) { _, _ in
                withAnimation(.snappy) {
                    proxy.scrollTo("local-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(LitterTheme.accent)
            Text("Private local conversation")
                .litterFont(.title3, weight: .bold)
                .foregroundStyle(LitterTheme.textPrimary)
            Text("Responses are generated by Apple’s system language model on this device. Nothing here is sent to an AI server by PocketKernel.")
                .litterFont(.subheadline)
                .foregroundStyle(LitterTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 28)
        .padding(.top, 72)
        .frame(maxWidth: .infinity)
    }

    private func localMessageBubble(_ message: AppleIntelligenceChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 42) }

            Text(message.text)
                .litterFont(.body)
                .foregroundStyle(message.role == .user ? Color.black : LitterTheme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    message.role == .user ? LitterTheme.accent : LitterTheme.surface,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )

            if message.role == .assistant { Spacer(minLength: 42) }
        }
        .padding(.horizontal, 16)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField("Message the on-device model", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .litterFont(.body)
                .foregroundStyle(LitterTheme.textPrimary)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(LitterTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(composerFocused ? LitterTheme.accent.opacity(0.55) : LitterTheme.textMuted.opacity(0.18))
                )

            Button {
                Task { await sendDraft() }
            } label: {
                Group {
                    if store.isResponding {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .black))
                    }
                }
                .frame(width: 46, height: 46)
                .foregroundStyle(Color.black)
                .background(canSend ? LitterTheme.accent : LitterTheme.textMuted.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !store.isResponding && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusColor: Color {
        switch store.runtimeStatus {
        case .available: return LitterTheme.accent
        case .unavailable: return LitterTheme.warning
        }
    }

    private var statusSymbol: String {
        switch store.runtimeStatus {
        case .available: return "checkmark.circle.fill"
        case .unavailable: return "exclamationmark.triangle.fill"
        }
    }

    private func sendDraft() async {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        draft = ""
        composerFocused = false
        await store.send(prompt)
    }

    private func sendInitialPromptIfNeeded() async {
        guard !didSendInitialPrompt,
              let initialPrompt,
              !initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        didSendInitialPrompt = true
        await store.send(initialPrompt)
    }
}
