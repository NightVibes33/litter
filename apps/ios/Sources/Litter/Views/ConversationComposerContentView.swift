import SwiftUI
import UIKit

struct ConversationComposerContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let attachments: [ConversationAttachment]
    let collaborationMode: AppModeKind
    let activePlanProgress: AppPlanProgressSnapshot?
    let pendingUserInputRequest: PendingUserInputRequest?
    let hasPendingPlanImplementation: Bool
    let activeTaskSummary: ConversationActiveTaskSummary?
    let queuedFollowUps: [AppQueuedFollowUpPreview]
    let pluginMentions: [PluginMentionSelection]
    let rateLimits: RateLimitSnapshot?
    let contextPercent: Int64?
    let isTurnActive: Bool
    let showModeChip: Bool
    let voiceManager: VoiceTranscriptionManager
    let allowsVoiceInput: Bool
    @Binding var showAttachMenu: Bool
    let onRemoveAttachment: (ConversationAttachment.ID) -> Void
    let onRespondToPendingUserInput: ([String: [String]]) -> Void
    let onImplementPlan: () -> Void
    let onDismissPlanImplementation: () -> Void
    let onSteerQueuedFollowUp: (AppQueuedFollowUpPreview) -> Void
    let onDeleteQueuedFollowUp: (AppQueuedFollowUpPreview) -> Void
    let onRemovePluginMention: (PluginMentionSelection) -> Void
    let onPasteImage: (UIImage) -> Void
    let onOpenModePicker: () -> Void
    let onSendText: () -> Void
    let onStopRecording: () -> Void
    let onStartRecording: () -> Void
    let onInterrupt: () -> Void
    @Binding var inputText: String
    @Binding var isComposerFocused: Bool
    @Binding var composerSelectionRange: NSRange

    init(
        attachments: [ConversationAttachment],
        collaborationMode: AppModeKind,
        activePlanProgress: AppPlanProgressSnapshot?,
        pendingUserInputRequest: PendingUserInputRequest?,
        hasPendingPlanImplementation: Bool = false,
        activeTaskSummary: ConversationActiveTaskSummary?,
        queuedFollowUps: [AppQueuedFollowUpPreview],
        pluginMentions: [PluginMentionSelection] = [],
        rateLimits: RateLimitSnapshot?,
        contextPercent: Int64?,
        isTurnActive: Bool,
        showModeChip: Bool = true,
        voiceManager: VoiceTranscriptionManager,
        allowsVoiceInput: Bool = true,
        showAttachMenu: Binding<Bool>,
        onRemoveAttachment: @escaping (ConversationAttachment.ID) -> Void,
        onRespondToPendingUserInput: @escaping ([String: [String]]) -> Void,
        onImplementPlan: @escaping () -> Void = {},
        onDismissPlanImplementation: @escaping () -> Void = {},
        onSteerQueuedFollowUp: @escaping (AppQueuedFollowUpPreview) -> Void,
        onDeleteQueuedFollowUp: @escaping (AppQueuedFollowUpPreview) -> Void,
        onRemovePluginMention: @escaping (PluginMentionSelection) -> Void = { _ in },
        onPasteImage: @escaping (UIImage) -> Void,
        onOpenModePicker: @escaping () -> Void,
        onSendText: @escaping () -> Void,
        onStopRecording: @escaping () -> Void,
        onStartRecording: @escaping () -> Void,
        onInterrupt: @escaping () -> Void,
        inputText: Binding<String>,
        isComposerFocused: Binding<Bool>,
        composerSelectionRange: Binding<NSRange> = .constant(NSRange(location: 0, length: 0))
    ) {
        self.attachments = attachments
        self.collaborationMode = collaborationMode
        self.activePlanProgress = activePlanProgress
        self.pendingUserInputRequest = pendingUserInputRequest
        self.hasPendingPlanImplementation = hasPendingPlanImplementation
        self.activeTaskSummary = activeTaskSummary
        self.queuedFollowUps = queuedFollowUps
        self.pluginMentions = pluginMentions
        self.rateLimits = rateLimits
        self.contextPercent = contextPercent
        self.isTurnActive = isTurnActive
        self.showModeChip = showModeChip
        self.voiceManager = voiceManager
        self.allowsVoiceInput = allowsVoiceInput
        _showAttachMenu = showAttachMenu
        self.onRemoveAttachment = onRemoveAttachment
        self.onRespondToPendingUserInput = onRespondToPendingUserInput
        self.onImplementPlan = onImplementPlan
        self.onDismissPlanImplementation = onDismissPlanImplementation
        self.onSteerQueuedFollowUp = onSteerQueuedFollowUp
        self.onDeleteQueuedFollowUp = onDeleteQueuedFollowUp
        self.onRemovePluginMention = onRemovePluginMention
        self.onPasteImage = onPasteImage
        self.onOpenModePicker = onOpenModePicker
        self.onSendText = onSendText
        self.onStopRecording = onStopRecording
        self.onStartRecording = onStartRecording
        self.onInterrupt = onInterrupt
        _inputText = inputText
        _isComposerFocused = isComposerFocused
        _composerSelectionRange = composerSelectionRange
    }

    var body: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(attachments) { attachment in
                            ConversationAttachmentPreviewChip(
                                attachment: attachment,
                                onRemove: { onRemoveAttachment(attachment.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }

            VStack(alignment: .trailing, spacing: 0) {
                if let activePlanProgress {
                    ConversationComposerPlanProgressView(progress: activePlanProgress)
                        .id(activePlanProgress.turnId)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                if let activeTaskSummary {
                    ConversationComposerActiveTaskRowView(summary: activeTaskSummary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                if let pendingUserInputRequest {
                    PendingUserInputPromptView(request: pendingUserInputRequest, onSubmit: onRespondToPendingUserInput)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                if hasPendingPlanImplementation {
                    PlanImplementationPromptView(
                        onImplement: onImplementPlan,
                        onDismiss: onDismissPlanImplementation
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                if !queuedFollowUps.isEmpty {
                    QueuedFollowUpsPreviewView(
                        previews: queuedFollowUps,
                        onSteer: onSteerQueuedFollowUp,
                        onDelete: onDeleteQueuedFollowUp
                    )
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                if !pluginMentions.isEmpty {
                    ConversationComposerPluginChipStrip(
                        plugins: pluginMentions,
                        onRemove: onRemovePluginMention
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                }

                ConversationComposerEntryRowView(
                    showAttachMenu: $showAttachMenu,
                    inputText: $inputText,
                    isComposerFocused: $isComposerFocused,
                    composerSelectionRange: $composerSelectionRange,
                    voiceManager: voiceManager,
                    isTurnActive: isTurnActive,
                    hasAttachment: !attachments.isEmpty,
                    allowsVoiceInput: allowsVoiceInput,
                    onPasteImage: onPasteImage,
                    onSendText: onSendText,
                    onStopRecording: onStopRecording,
                    onStartRecording: onStartRecording,
                    onInterrupt: onInterrupt
                )

                ConversationComposerContextBarView(
                    rateLimits: rateLimits,
                    contextPercent: contextPercent
                )
            }
        }
        .frame(maxWidth: LitterPlatform.isRegularSurface(horizontalSizeClass: horizontalSizeClass) ? 760 : .infinity)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}


private struct ConversationAttachmentPreviewChip: View {
    let attachment: ConversationAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let image = attachment.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: attachment.kind.iconName)
                        .font(LitterFont.styled(size: 18, weight: .semibold))
                        .foregroundStyle(attachment.kind == .archive ? LitterTheme.warning : LitterTheme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 42, height: 42)
            .background(LitterTheme.surface.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.displayName)
                    .litterFont(.caption, weight: .semibold)
                    .foregroundStyle(LitterTheme.textPrimary)
                    .lineLimit(1)
                Text(attachment.fakefsPath ?? attachment.detail)
                    .litterMonoFont(size: 10, weight: .regular)
                    .foregroundStyle(LitterTheme.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: 190, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(LitterFont.styled(size: 16, weight: .bold))
                    .foregroundStyle(LitterTheme.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attachment")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .modifier(GlassRoundedRectModifier(cornerRadius: 18))
    }
}

private struct ConversationComposerPluginChipStrip: View {
    let plugins: [PluginMentionSelection]
    let onRemove: (PluginMentionSelection) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(plugins, id: \.path) { plugin in
                    HStack(spacing: 4) {
                        Image(systemName: "puzzlepiece.extension.fill")
                            .litterFont(size: 10, weight: .semibold)
                            .foregroundStyle(LitterTheme.accent)
                        Text(plugin.displayTitle)
                            .litterFont(.caption, weight: .semibold)
                            .foregroundStyle(LitterTheme.accent)
                            .lineLimit(1)
                        Button {
                            onRemove(plugin)
                        } label: {
                            Image(systemName: "xmark")
                                .litterFont(size: 9, weight: .bold)
                                .foregroundStyle(LitterTheme.accent)
                                .padding(3)
                                .background(Circle().fill(LitterTheme.accent.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove plugin \(plugin.displayTitle)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LitterTheme.accent.opacity(0.12))
                    )
                }
            }
        }
    }
}

struct ConversationComposerModeChip: View {
    let mode: AppModeKind
    let onTap: () -> Void

    private var label: String {
        switch mode {
        case .plan:
            return "Plan"
        case .`default`:
            return "Default"
        }
    }

    private var foreground: Color {
        mode == .plan ? Color.black : LitterTheme.textPrimary
    }

    private var background: Color {
        mode == .plan ? LitterTheme.accent : LitterTheme.surfaceLight
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(label)
                    .litterFont(.caption, weight: .semibold)
                Image(systemName: "chevron.up.chevron.down")
                    .litterFont(size: 10, weight: .semibold)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(background))
        }
        .buttonStyle(.plain)
    }
}

private struct ConversationComposerPlanProgressView: View {
    let progress: AppPlanProgressSnapshot
    @State private var isExpanded = true

    private var completedCount: Int {
        progress.plan.filter { $0.status == .completed }.count
    }

    private var currentStepText: String {
        guard let step = currentStep?.step.trimmingCharacters(in: .whitespacesAndNewlines),
              !step.isEmpty else {
            return progress.plan.isEmpty ? "No plan task" : "Plan complete"
        }
        return step
    }

    private var currentStep: AppPlanStep? {
        progress.plan.first(where: { $0.status == .inProgress })
            ?? progress.plan.first(where: { $0.status == .pending })
            ?? progress.plan.last(where: { $0.status == .completed })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    headerContent
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse plan progress" : "Expand plan progress")

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LitterTheme.codeBackground.opacity(0.92))
        )
    }

    private var headerContent: some View {
        Group {
            Image(systemName: "list.bullet.clipboard")
                .litterFont(size: 12, weight: .semibold)
                .foregroundStyle(LitterTheme.accent)
            Text(isExpanded ? "Plan Progress" : "Plan")
                .litterFont(.caption, weight: .semibold)
                .foregroundStyle(LitterTheme.textPrimary)
            Text("\(completedCount)/\(progress.plan.count)")
                .litterMonoFont(size: 11, weight: .semibold)
                .foregroundStyle(LitterTheme.textSecondary)

            if !isExpanded {
                Text(currentStepText)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            } else {
                Spacer(minLength: 0)
            }

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .litterFont(size: 10, weight: .semibold)
                .foregroundStyle(LitterTheme.textMuted)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if let explanation = progress.explanation?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explanation.isEmpty {
            Text(explanation)
                .litterFont(.caption)
                .foregroundStyle(LitterTheme.textSecondary)
        }

        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(progress.plan.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: iconName(for: step.status))
                        .litterFont(size: 11, weight: .semibold)
                        .foregroundStyle(iconColor(for: step.status))
                        .padding(.top, 2)
                    Text("\(index + 1).")
                        .litterMonoFont(size: 11, weight: .semibold)
                        .foregroundStyle(LitterTheme.textMuted)
                        .padding(.top, 1)
                    Text(step.step)
                        .litterFont(.caption)
                        .foregroundStyle(LitterTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func iconName(for status: AppPlanStepStatus) -> String {
        switch status {
        case .completed:
            return "checkmark.circle.fill"
        case .inProgress:
            return "circle.fill"
        case .pending:
            return "circle"
        }
    }

    private func iconColor(for status: AppPlanStepStatus) -> Color {
        switch status {
        case .completed:
            return LitterTheme.success
        case .inProgress:
            return LitterTheme.warning
        case .pending:
            return LitterTheme.textMuted
        }
    }
}

private struct ConversationComposerActiveTaskRowView: View {
    let summary: ConversationActiveTaskSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .litterFont(size: 11, weight: .semibold)
                .foregroundColor(LitterTheme.warning)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(summary.title)
                        .litterFont(.caption, weight: .semibold)
                        .foregroundColor(LitterTheme.textPrimary)

                    Text(summary.progressLabel)
                        .litterMonoFont(size: 10, weight: .semibold)
                        .foregroundColor(LitterTheme.warning)
                }

                Text(summary.detail)
                    .litterFont(.caption2)
                    .foregroundColor(LitterTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LitterTheme.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
