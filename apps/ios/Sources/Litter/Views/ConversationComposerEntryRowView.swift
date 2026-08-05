import SwiftUI
import UIKit

struct ConversationComposerEntryRowView: View {
    @Binding var showAttachMenu: Bool
    @Binding var inputText: String
    @Binding var isComposerFocused: Bool
    @Binding var composerSelectionRange: NSRange
    let voiceManager: VoiceTranscriptionManager
    let isTurnActive: Bool
    let hasAttachment: Bool
    let allowsVoiceInput: Bool
    let onPasteImage: (UIImage) -> Void
    let onSendText: () -> Void
    let onStopRecording: () -> Void
    let onStartRecording: () -> Void
    let onInterrupt: () -> Void

    @StateObject private var providerStore = AIProviderStore.shared
    @StateObject private var localAgentBridge = AppleLocalAgentBridge()
    @AppStorage("workDir") private var workDir = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    ).first?.path ?? "/root"
    @State private var showExpanded: Bool = false
    @State private var showLocalAgentSheet: Bool = false

    private enum Metrics {
        static let controlSize: CGFloat = 44
        static let inputCornerRadius: CGFloat = controlSize / 2
        static let trailingControlSize: CGFloat = 44
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 6
    }

    init(
        showAttachMenu: Binding<Bool>,
        inputText: Binding<String>,
        isComposerFocused: Binding<Bool>,
        composerSelectionRange: Binding<NSRange> = .constant(NSRange(location: 0, length: 0)),
        voiceManager: VoiceTranscriptionManager,
        isTurnActive: Bool,
        hasAttachment: Bool,
        allowsVoiceInput: Bool = true,
        onPasteImage: @escaping (UIImage) -> Void,
        onSendText: @escaping () -> Void,
        onStopRecording: @escaping () -> Void,
        onStartRecording: @escaping () -> Void,
        onInterrupt: @escaping () -> Void
    ) {
        _showAttachMenu = showAttachMenu
        _inputText = inputText
        _isComposerFocused = isComposerFocused
        _composerSelectionRange = composerSelectionRange
        self.voiceManager = voiceManager
        self.isTurnActive = isTurnActive
        self.hasAttachment = hasAttachment
        self.allowsVoiceInput = allowsVoiceInput
        self.onPasteImage = onPasteImage
        self.onSendText = onSendText
        self.onStopRecording = onStopRecording
        self.onStartRecording = onStartRecording
        self.onInterrupt = onInterrupt
    }

    private var hasText: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSend: Bool {
        hasText || hasAttachment
    }

    private var normalizedWorkDirectory: String {
        let trimmed = workDir.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "/root" : trimmed
    }

    private var usesAppleOnDeviceRoute: Bool {
        let settings = providerStore.globalModelSettings
        switch settings.routingMode {
        case .appleOnDevice:
            return true
        case .automatic:
            let appleProviderId = AIProviderProfile.appleOnDevice().id
            return settings.preferredProviderId == nil
                || settings.preferredProviderId == appleProviderId
        case .openAI, .openAICompatible:
            return false
        }
    }

    /// Show the expand affordance once the composer is multi-line or starts to
    /// wrap, matching ChatGPT's behaviour. Short prompts stay clutter-free.
    private var shouldShowExpand: Bool {
        !voiceManager.isRecording
            && !voiceManager.isTranscribing
            && (inputText.contains("\n") || inputText.count > 60)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if !voiceManager.isRecording && !voiceManager.isTranscribing && !isTurnActive {
                Button {
                    showAttachMenu = true
                } label: {
                    Image(systemName: "plus")
                        .font(LitterFont.styled(size: 20, weight: .semibold))
                        .foregroundColor(LitterTheme.textPrimary)
                        .frame(width: Metrics.controlSize, height: Metrics.controlSize)
                        .modifier(GlassCircleModifier())
                }
                .padding(4)
                .contentShape(Rectangle())
                .padding(-4)
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Attach")
                .zIndex(1)
            }

            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    ConversationComposerTextView(
                        text: $inputText,
                        isFocused: $isComposerFocused,
                        selectedRange: $composerSelectionRange,
                        onPasteImage: onPasteImage,
                        onHardwareSubmit: {
                            if canSend { handleSendText() }
                        }
                    )

                    if inputText.isEmpty {
                        Text("Message litter...")
                            .font(LitterFont.styled(size: 17))
                            .foregroundColor(LitterTheme.textMuted)
                            .padding(.leading, 16)
                            .padding(.top, 11)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if voiceManager.isRecording {
                    AudioWaveformView(level: voiceManager.audioLevel)
                        .frame(width: 48, height: 20)

                    Button(action: onStopRecording) {
                        Image(systemName: "stop.circle.fill")
                            .font(LitterFont.styled(size: 28))
                            .foregroundColor(LitterTheme.accentStrong)
                            .frame(width: Metrics.trailingControlSize, height: Metrics.trailingControlSize)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityLabel("Stop recording")
                } else if voiceManager.isTranscribing {
                    ProgressView()
                        .tint(LitterTheme.accent)
                        .frame(width: Metrics.trailingControlSize, height: Metrics.trailingControlSize)
                } else if allowsVoiceInput {
                    Button(action: onStartRecording) {
                        Image(systemName: "mic.fill")
                            .font(LitterFont.styled(size: 18))
                            .foregroundColor(LitterTheme.textSecondary)
                            .frame(width: Metrics.trailingControlSize, height: Metrics.trailingControlSize)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityLabel("Dictate")
                }
            }
            .frame(maxWidth: .infinity, minHeight: Metrics.controlSize)
            .modifier(GlassRoundedRectModifier(cornerRadius: Metrics.inputCornerRadius))
            .overlay(alignment: .topTrailing) {
                if shouldShowExpand {
                    Button {
                        showExpanded = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(LitterFont.styled(size: 12, weight: .semibold))
                            .foregroundColor(LitterTheme.textSecondary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .hoverEffect(.highlight)
                    .padding(.top, 2)
                    .padding(.trailing, 6)
                    .accessibilityLabel("Expand composer")
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: shouldShowExpand)

            if canSend {
                Button(action: handleSendText) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(LitterFont.styled(size: 30))
                        .foregroundColor(LitterTheme.accent)
                        .frame(width: Metrics.trailingControlSize, height: Metrics.trailingControlSize)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .disabled(voiceManager.isRecording || voiceManager.isTranscribing)
                .opacity(voiceManager.isRecording || voiceManager.isTranscribing ? 0.45 : 1)
                .accessibilityLabel(usesAppleOnDeviceRoute && !hasAttachment ? "Send on device" : "Send")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if isTurnActive && !canSend {
                Button(action: onInterrupt) {
                    Text("Cancel")
                        .font(LitterFont.styled(size: 15, weight: .medium))
                        .foregroundColor(LitterTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: Metrics.controlSize)
                        .modifier(GlassCapsuleModifier())
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isTurnActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: canSend)
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.top, Metrics.verticalPadding)
        .padding(.bottom, Metrics.verticalPadding)
        .fullScreenCover(isPresented: $showExpanded) {
            ConversationComposerExpandedView(
                inputText: $inputText,
                isPresented: $showExpanded,
                onPasteImage: onPasteImage,
                onSend: handleSendText,
                hasAttachment: hasAttachment
            )
        }
        .sheet(isPresented: $showLocalAgentSheet) {
            AppleLocalAgentBridgeSheet(
                bridge: localAgentBridge,
                workDirectory: normalizedWorkDirectory
            )
        }
    }

    private func handleSendText() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard usesAppleOnDeviceRoute,
              !hasAttachment,
              !isTurnActive,
              !prompt.isEmpty else {
            onSendText()
            return
        }

        inputText = ""
        composerSelectionRange = NSRange(location: 0, length: 0)
        isComposerFocused = false
        showExpanded = false
        localAgentBridge.reset()
        showLocalAgentSheet = true

        let context = """
        Current working directory: \(normalizedWorkDirectory)
        Resolve relative command and filesystem paths against this directory.
        The app will require explicit user approval before executing any action.
        """

        Task {
            await localAgentBridge.submit(request: prompt, context: context)
        }
    }
}
