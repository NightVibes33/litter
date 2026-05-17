import SwiftUI
import WatchKit

/// 1 · Task pages — the watch's home is one full-screen page per task plus a
/// trailing "new task" page. Crown rotation switches tasks; each page has
/// glance-sized status + content and Open/Hide CTAs at the bottom. Falls back
/// to centered empty states when there are no tasks (or no data yet).
struct HomeScreen: View {
    @EnvironmentObject var store: WatchAppStore
    @EnvironmentObject var theme: WatchThemeStore

    var body: some View {
        Group {
            if !store.hasData {
                WatchEmptyState(
                    icon: "iphone.gen3",
                    title: store.isReachable ? "syncing…" : "open litter on iphone",
                    subtitle: store.isReachable ? nil : "the watch shows what the phone knows."
                )
            } else if store.tasks.isEmpty {
                WatchEmptyState(
                    icon: "sparkles",
                    title: "no tasks yet",
                    subtitle: "start a conversation on iphone."
                )
            } else {
                pagedTasks
            }
        }
        .containerBackground(theme.backgroundGradient, for: .navigation)
    }

    private var pagedTasks: some View {
        TabView(selection: tabSelection) {
            ForEach(store.tasks) { task in
                TaskPage(task: task)
                    .tag(Selection.task(task.id))
            }
            NewTaskPage()
                .tag(Selection.newTask)
        }
        .tabViewStyle(.verticalPage)
    }

    // MARK: - Selection binding

    /// Backs the `TabView`'s selection. Folded through a local enum so the
    /// trailing "new task" page can coexist with task ids without collisions,
    /// while still writing the focused-task id back to the store.
    private enum Selection: Hashable {
        case task(String)
        case newTask
    }

    private var tabSelection: Binding<Selection> {
        Binding(
            get: {
                if let id = store.focusedTaskId,
                   store.tasks.contains(where: { $0.id == id }) {
                    return .task(id)
                }
                return store.tasks.first.map { .task($0.id) } ?? .newTask
            },
            set: { new in
                switch new {
                case .task(let id): store.focusedTaskId = id
                case .newTask:      break
                }
            }
        )
    }
}

// MARK: - Per-task page

/// One full-screen page of task content. Larger fonts than the prior row,
/// with status/header chip up top, identity strip + subtitle in the middle,
/// and Open / Hide CTAs pinned to the bottom.
private struct TaskPage: View {
    @EnvironmentObject var store: WatchAppStore
    @EnvironmentObject var theme: WatchThemeStore
    let task: WatchTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusChip(status: task.status)
                Spacer(minLength: 4)
                if store.lastSyncIsStale && !store.isReachable {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.textMuted)
                }
                HeaderBadges()
                if !task.relativeTime.isEmpty {
                    Text(task.relativeTime)
                        .font(WatchTheme.mono(10))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize()
                }
            }

            Text(task.title)
                .font(WatchTheme.mono(15, weight: .bold))
                .foregroundStyle(task.status == .running ? theme.accent : theme.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            identityStrip

            if let subtitle = task.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(WatchTheme.mono(11))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if task.status == .running, let line = telemetryLine {
                Text(line)
                    .font(WatchTheme.mono(10))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            ctaRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: - Pieces

    private var identityStrip: some View {
        HStack(spacing: 4) {
            Text(task.serverName)
                .foregroundStyle(theme.accent.opacity(0.7))
                .lineLimit(1)
            if let model = task.model, !model.isEmpty {
                dot
                Text(model)
                    .foregroundStyle(theme.textSecondary.opacity(0.85))
                    .lineLimit(1)
            }
            if let basename = cwdBasename {
                dot
                Text(basename)
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .font(WatchTheme.mono(10))
    }

    private var ctaRow: some View {
        HStack(spacing: 6) {
            NavigationLink {
                TaskDetailScreen(task: task)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("open")
                        .font(WatchTheme.mono(11, weight: .bold))
                }
                .frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(theme.textOnAccent)
                .background(
                    Capsule().fill(
                        LinearGradient(colors: [theme.accentSoft, theme.accent],
                                       startPoint: .top, endPoint: .bottom)
                    )
                )
            }
            .buttonStyle(.plain)

            Button {
                WKInterfaceDevice.current().play(.click)
                WatchSessionBridge.shared.sendHomeHide(
                    serverId: task.serverId,
                    threadId: task.threadId
                )
            } label: {
                Image(systemName: "eye.slash")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 32, height: 28)
                    .foregroundStyle(theme.textSecondary)
                    .background(
                        Capsule()
                            .fill(theme.surfaceLight)
                            .overlay(Capsule().stroke(theme.borderHi, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide task")
        }
    }

    private var dot: some View {
        Text("·").foregroundStyle(theme.textMuted.opacity(0.6))
    }

    private var cwdBasename: String? {
        guard let cwd = task.cwd, !cwd.isEmpty else { return nil }
        return (cwd as NSString).lastPathComponent
    }

    private var subtitleColor: Color {
        switch task.status {
        case .running:       return theme.accent
        case .needsApproval: return theme.warning
        case .idle:          return theme.textMuted
        case .error:         return theme.danger
        }
    }

    private var telemetryLine: String? {
        var parts: [String] = []
        if let t = task.turnCount, t > 0 { parts.append("\(t) turns") }
        let adds = task.diffAdditions ?? 0
        let rems = task.diffDeletions ?? 0
        if adds > 0 || rems > 0 { parts.append("+\(adds) −\(rems)") }
        if let pct = task.contextPercent, pct > 0 { parts.append("\(pct)%") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Trailing "new task" page

private struct NewTaskPage: View {
    @EnvironmentObject var theme: WatchThemeStore

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            NavigationLink {
                VoiceScreen()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.textOnAccent)
                        .frame(width: 56, height: 56)
                        .background(
                            Circle().fill(
                                LinearGradient(colors: [theme.accentSoft, theme.accent],
                                               startPoint: .top, endPoint: .bottom)
                            )
                        )
                    Text("new task")
                        .font(WatchTheme.mono(13, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                    Text("dictate a prompt")
                        .font(WatchTheme.mono(10))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
    }
}

// MARK: - Reused chips

private struct StatusChip: View {
    @EnvironmentObject var theme: WatchThemeStore
    let status: WatchTask.Status

    var body: some View {
        HStack(spacing: 4) {
            bullet
            Text(label)
                .font(WatchTheme.mono(10, weight: .bold))
                .foregroundStyle(color)
        }
    }

    @ViewBuilder private var bullet: some View {
        switch status {
        case .running:
            PulsingDot(color: theme.accent, size: 6)
        case .needsApproval:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(theme.warning)
        case .idle:
            Circle().fill(theme.textSecondary).frame(width: 5, height: 5)
        case .error:
            Circle().fill(theme.danger).frame(width: 5, height: 5)
        }
    }

    private var label: String {
        switch status {
        case .running:       return "running"
        case .needsApproval: return "approval"
        case .idle:          return "idle"
        case .error:         return "error"
        }
    }

    private var color: Color {
        switch status {
        case .running:       return theme.accent
        case .needsApproval: return theme.warning
        case .idle:          return theme.textSecondary
        case .error:         return theme.danger
        }
    }
}

private struct HeaderBadges: View {
    @EnvironmentObject var store: WatchAppStore
    @EnvironmentObject var theme: WatchThemeStore

    var body: some View {
        HStack(spacing: 6) {
            if store.approvalsTaskCount > 0 {
                Badge(color: theme.warning, count: store.approvalsTaskCount)
            }
            if store.runningTaskCount > 0 {
                Badge(color: theme.success, count: store.runningTaskCount)
            }
        }
    }
}

private struct Badge: View {
    @EnvironmentObject var theme: WatchThemeStore
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(count)")
                .font(WatchTheme.mono(10))
                .foregroundStyle(theme.textSecondary)
        }
    }
}

#if DEBUG
#Preview("tasks") {
    NavigationStack {
        HomeScreen()
            .environmentObject(WatchAppStore.previewStore())
            .environmentObject(WatchThemeStore.shared)
    }
}

#Preview("empty") {
    NavigationStack {
        HomeScreen()
            .environmentObject(WatchAppStore())
            .environmentObject(WatchThemeStore.shared)
    }
}
#endif
