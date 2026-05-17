import SwiftUI

/// Per-task detail — shows the task's steps, subtitle, and nav links to
/// its transcript or a reply composer. Requesting focus on this task from
/// the phone causes the next snapshot to carry this task's transcript.
struct TaskDetailScreen: View {
    @EnvironmentObject var store: WatchAppStore
    @EnvironmentObject var theme: WatchThemeStore
    @Environment(\.isLuminanceReduced) private var isAOD
    let task: WatchTask

    var body: some View {
        // Prefer the freshest version from the store — the task param might
        // be stale if we've been on this screen across multiple snapshots.
        let current = store.tasks.first(where: { $0.id == task.id }) ?? task

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                header(for: current)

                Text(current.title)
                    .font(WatchTheme.mono(13, weight: .bold))
                    .foregroundStyle(isAOD ? theme.textSecondary : theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !isAOD {
                    if let subtitle = current.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(WatchTheme.mono(10))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if current.status == .needsApproval,
                       let approval = store.pendingApproval,
                       current.pendingApprovalId == approval.id {
                        NavigationLink {
                            ApprovalScreen()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(theme.warning)
                                Text("review approval")
                                    .font(WatchTheme.mono(11, weight: .bold))
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(theme.warning.opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(theme.warning.opacity(0.4), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !current.steps.isEmpty {
                        WatchEyebrow(text: "recent", size: 9)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(current.steps) { step in
                                StepRow(step: step)
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        NavigationLink {
                            TranscriptScreen()
                        } label: {
                            actionLabel("transcript", icon: "text.bubble")
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            VoiceScreen()
                        } label: {
                            actionLabel("reply", icon: "mic.fill", accent: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .onAppear {
            store.focus(on: current)
        }
        .containerBackground(theme.backgroundGradient, for: .navigation)
    }

    private func header(for task: WatchTask) -> some View {
        HStack(spacing: 6) {
            switch task.status {
            case .running:
                if isAOD {
                    Circle().fill(theme.textSecondary).frame(width: 6, height: 6)
                } else {
                    PulsingDot(color: theme.accent, size: 7)
                }
                Text("running")
                    .font(WatchTheme.mono(10, weight: .bold))
                    .foregroundStyle(isAOD ? theme.textSecondary : theme.accent)
            case .needsApproval:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isAOD ? theme.textSecondary : theme.warning)
                Text("needs approval")
                    .font(WatchTheme.mono(10, weight: .bold))
                    .foregroundStyle(isAOD ? theme.textSecondary : theme.warning)
            case .idle:
                Circle().fill(theme.textSecondary).frame(width: 6, height: 6)
                Text("idle")
                    .font(WatchTheme.mono(10, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
            case .error:
                Circle().fill(isAOD ? theme.textSecondary : theme.danger).frame(width: 6, height: 6)
                Text("error")
                    .font(WatchTheme.mono(10, weight: .bold))
                    .foregroundStyle(isAOD ? theme.textSecondary : theme.danger)
            }
            Spacer()
            if !isAOD {
                Text(task.serverName)
                    .font(WatchTheme.mono(9))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !task.relativeTime.isEmpty {
                Text(task.relativeTime)
                    .font(WatchTheme.mono(9))
                    .foregroundStyle(theme.textMuted)
            }
        }
    }

    private func actionLabel(_ label: String, icon: String, accent: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(WatchTheme.mono(11, weight: .bold))
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .foregroundStyle(accent ? theme.textOnAccent : theme.textPrimary)
        .background(
            Capsule().fill(accent
                ? LinearGradient(colors: [theme.accentSoft, theme.accent],
                                 startPoint: .top, endPoint: .bottom)
                : LinearGradient(colors: [theme.surfaceLight, theme.surfaceLight],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                Capsule().stroke(accent ? Color.clear : theme.borderHi, lineWidth: 1)
            )
        )
    }
}

private struct StepRow: View {
    @EnvironmentObject var theme: WatchThemeStore
    let step: WatchTaskStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StepBullet(state: step.state)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.tool)
                    .font(WatchTheme.mono(11, weight: step.state == .active ? .bold : .regular))
                    .foregroundStyle(color(for: step.state))
                    .lineLimit(1)
                if !step.arg.isEmpty {
                    Text(step.arg)
                        .font(WatchTheme.mono(9))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func color(for state: WatchTaskStep.State) -> Color {
        switch state {
        case .active:  return theme.accent
        case .done:    return theme.textPrimary
        case .pending: return theme.textSecondary
        }
    }
}

private struct StepBullet: View {
    @EnvironmentObject var theme: WatchThemeStore
    let state: WatchTaskStep.State
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Circle().stroke(stroke, lineWidth: 1)

            switch state {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .heavy))
                    .foregroundStyle(theme.success)
            case .active:
                Circle()
                    .fill(theme.accent)
                    .frame(width: 4, height: 4)
                    .opacity(pulse ? 0.3 : 1)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
            case .pending:
                EmptyView()
            }
        }
    }

    private var fill: Color {
        switch state {
        case .done:    return theme.success.opacity(0.15)
        case .active:  return theme.accent.opacity(0.2)
        case .pending: return theme.surfaceLight
        }
    }

    private var stroke: Color {
        switch state {
        case .done:    return theme.success.opacity(0.4)
        case .active:  return theme.accent
        case .pending: return theme.borderHi
        }
    }
}

#if DEBUG
#Preview("running") {
    NavigationStack {
        TaskDetailScreen(task: WatchPreviewFixtures.tasks[0])
            .environmentObject(WatchAppStore.previewStore())
            .environmentObject(WatchThemeStore.shared)
    }
}

#Preview("idle") {
    NavigationStack {
        TaskDetailScreen(task: WatchPreviewFixtures.tasks[1])
            .environmentObject(WatchAppStore.previewStore())
            .environmentObject(WatchThemeStore.shared)
    }
}

#Preview("aod") {
    NavigationStack {
        TaskDetailScreen(task: WatchPreviewFixtures.tasks[0])
            .environmentObject(WatchAppStore.previewStore())
            .environmentObject(WatchThemeStore.shared)
            .environment(\.isLuminanceReduced, true)
    }
}
#endif
