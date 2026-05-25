import ActivityKit
import Foundation

@MainActor
final class TurnLiveActivityController {
    private var activity: Activity<CodexTurnAttributes>?
    private var activeKey: ThreadKey?
    private var startDate: Date?
    private var outputSnippet: String?
    private var outputSnippetSourceItemId: String?
    private var lastUpdateTime: CFAbsoluteTime = 0
    private var didCleanupStaleActivities = false

    private func cleanupStaleActivities() {
        guard !didCleanupStaleActivities else { return }
        didCleanupStaleActivities = true
        for stale in Activity<CodexTurnAttributes>.activities {
            let state = CodexTurnAttributes.ContentState(
                phase: .completed, elapsedSeconds: 0, toolCallCount: 0,
                activeThreadCount: 0, fileChangeCount: 0, contextPercent: 0
            )
            Task {
                await stale.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
    }

    func sync(_ snapshot: AppSnapshotRecord?) {
        cleanupStaleActivities()

        guard let snapshot else {
            endCurrent(phase: .completed, snapshot: nil)
            return
        }

        let activeThreads = snapshot.threadsWithTrackedTurns

        if activeThreads.isEmpty {
            endCurrent(phase: .completed, snapshot: snapshot)
            return
        }

        // Pick the best thread to show: prefer the active thread, else most recent.
        let best = activeThreads.first(where: { $0.key == snapshot.activeThread })
            ?? activeThreads.first!

        if let currentKey = activeKey, currentKey != best.key {
            // Active thread changed — end old, start new.
            endCurrent(phase: .completed, snapshot: snapshot)
        }

        if activity == nil {
            start(for: best, activeCount: activeThreads.count, snapshot: snapshot)
        } else {
            update(for: best, activeCount: activeThreads.count, snapshot: snapshot)
        }
    }

    private func start(for thread: AppThreadSnapshot, activeCount: Int, snapshot: AppSnapshotRecord) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let now = Date()
        let attributes = CodexTurnAttributes(
            threadId: thread.key.threadId,
            model: thread.resolvedModel,
            cwd: thread.info.cwd ?? "",
            startDate: now,
            prompt: String(thread.resolvedPreview.prefix(120))
        )
        let state = CodexTurnAttributes.ContentState(
            phase: .thinking,
            elapsedSeconds: 0,
            toolCallCount: 0,
            activeThreadCount: max(1, activeCount),
            fileChangeCount: 0,
            contextPercent: thread.contextPercent
        )
        activeKey = thread.key
        startDate = now
        outputSnippet = nil
        outputSnippetSourceItemId = nil
        lastUpdateTime = 0
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {}

        writeRunningTurnSnapshot(for: thread, startDate: now, snapshot: snapshot)
    }

    private func update(for thread: AppThreadSnapshot, activeCount: Int, snapshot: AppSnapshotRecord) {
        guard let activity else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastUpdateTime > 2.0 else { return }

        if let assistantSnippet = thread.latestAssistantSnippetSnapshot,
           outputSnippetSourceItemId != assistantSnippet.sourceItemId || outputSnippet != assistantSnippet.snippet {
            outputSnippetSourceItemId = assistantSnippet.sourceItemId
            outputSnippet = assistantSnippet.snippet
        }

        let state = CodexTurnAttributes.ContentState(
            phase: .thinking,
            elapsedSeconds: Int(Date().timeIntervalSince(startDate ?? Date())),
            toolCallCount: 0,
            activeThreadCount: max(1, activeCount),
            outputSnippet: outputSnippet,
            fileChangeCount: 0,
            contextPercent: thread.contextPercent
        )
        lastUpdateTime = now
        Task {
            await activity.update(.init(state: state, staleDate: Date(timeIntervalSinceNow: 60)))
        }

        writeRunningTurnSnapshot(for: thread, startDate: startDate ?? Date(), snapshot: snapshot)
    }

    func updateBackgroundWake(for thread: AppThreadSnapshot, pushCount: Int) {
        guard let activity else { return }
        if let snapshot = thread.latestAssistantSnippetSnapshot,
           outputSnippetSourceItemId != snapshot.sourceItemId || outputSnippet != snapshot.snippet {
            outputSnippetSourceItemId = snapshot.sourceItemId
            outputSnippet = snapshot.snippet
        }

        let state = CodexTurnAttributes.ContentState(
            phase: .thinking,
            elapsedSeconds: Int(Date().timeIntervalSince(startDate ?? Date())),
            toolCallCount: 0,
            activeThreadCount: 1,
            outputSnippet: outputSnippet,
            pushCount: pushCount,
            fileChangeCount: 0,
            contextPercent: thread.contextPercent
        )
        lastUpdateTime = CFAbsoluteTimeGetCurrent()
        Task {
            await activity.update(.init(state: state, staleDate: Date(timeIntervalSinceNow: 60)))
        }
    }

    func endCurrent(phase: CodexTurnAttributes.ContentState.Phase, snapshot: AppSnapshotRecord?) {
        guard let activity else { return }
        let thread = activeKey.flatMap { snapshot?.threadSnapshot(for: $0) }
        let state = CodexTurnAttributes.ContentState(
            phase: phase,
            elapsedSeconds: Int(Date().timeIntervalSince(startDate ?? Date())),
            toolCallCount: 0,
            activeThreadCount: 0,
            outputSnippet: outputSnippet,
            fileChangeCount: 0,
            contextPercent: thread?.contextPercent ?? 0
        )
        Task {
            await activity.end(
                .init(state: state, staleDate: Date(timeIntervalSinceNow: 60)),
                dismissalPolicy: .after(.now + 4)
            )
        }
        self.activity = nil
        activeKey = nil
        startDate = nil
        outputSnippet = nil
        outputSnippetSourceItemId = nil
        lastUpdateTime = 0

        // Clear the watch Smart Stack mirror so the LitterRunningTurnWidget
        // hides as soon as the turn ends.
        RunningTurnStore.clear()
    }

    /// Project the running thread into the App Group payload the watch's
    /// `LitterRunningTurnWidget` reads. Kept side-effect-only so the live
    /// activity write path stays the source of truth for "turn running".
    private func writeRunningTurnSnapshot(
        for thread: AppThreadSnapshot,
        startDate: Date,
        snapshot: AppSnapshotRecord
    ) {
        let payload = Self.makeRunningTurnSnapshot(
            for: thread,
            startDate: startDate,
            snapshot: snapshot
        )
        RunningTurnStore.write(payload)
    }

    /// Static so unit tests can validate the projection without an
    /// `ActivityKit`-backed instance.
    static func makeRunningTurnSnapshot(
        for thread: AppThreadSnapshot,
        startDate: Date,
        snapshot: AppSnapshotRecord
    ) -> RunningTurnSnapshot {
        let serverName: String = {
            if let server = snapshot.servers.first(where: { $0.serverId == thread.key.serverId }) {
                return server.displayName.isEmpty ? thread.key.serverId : server.displayName
            }
            return thread.key.serverId
        }()
        let summary = snapshot.sessionSummaries.first(where: { $0.key == thread.key })
        let title: String = {
            if let summary, !summary.title.isEmpty { return summary.title }
            let preview = thread.resolvedPreview.trimmingCharacters(in: .whitespacesAndNewlines)
            return preview.isEmpty ? "untitled task" : String(preview.prefix(60))
        }()
        let model = thread.resolvedModel.isEmpty ? nil : thread.resolvedModel
        let lastTool: String? = {
            if let label = summary?.lastToolLabel, !label.isEmpty {
                return String(label.prefix(48))
            }
            return nil
        }()
        return RunningTurnSnapshot(
            taskId: "\(thread.key.serverId):\(thread.key.threadId)",
            title: title,
            serverName: serverName,
            model: model,
            startedAtMs: Int64(startDate.timeIntervalSince1970 * 1000),
            lastTool: lastTool
        )
    }
}
