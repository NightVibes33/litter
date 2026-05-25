import Foundation

/// Codable App Group payload mirroring the iPhone's Live Activity for the
/// currently running turn. Written by `TurnLiveActivityController`
/// (start/update/end) so the watch's Smart Stack widget can render the same
/// turn without re-deriving from the snapshot push.
///
/// Schema is versioned through the App Group key (`running.turn.v1`). Add a
/// new key (`running.turn.v2`) before breaking shape.
struct RunningTurnSnapshot: Codable, Equatable {
    /// `{serverId}:{threadId}` so the widget can deep-link via
    /// `litter-watch://task/{taskId}` and match a snapshot row on the watch.
    let taskId: String
    let title: String
    let serverName: String
    let model: String?
    /// Wall-clock epoch ms when this turn started.
    let startedAtMs: Int64
    /// Most recent tool-call label, e.g. `edit_file src/auth.go` — optional
    /// because the turn may be in `thinking` with no tool yet.
    let lastTool: String?
}

/// Reads/writes the running-turn snapshot in the shared App Group.
enum RunningTurnStore {
    static let appGroup = "group.com.sigkitten.litter"
    static let key = "running.turn.v1"
    /// Snapshots older than this are treated as stale — the widget hides
    /// rather than show a frozen turn that may have ended off-screen.
    static let staleAfter: TimeInterval = 30 * 60

    static func current() -> RunningTurnSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroup),
            let data = defaults.data(forKey: key)
        else { return nil }
        return try? JSONDecoder().decode(RunningTurnSnapshot.self, from: data)
    }

    static func write(_ snapshot: RunningTurnSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.removeObject(forKey: key)
    }

    /// True when the snapshot was written more than `staleAfter` ago.
    static func isStale(_ snapshot: RunningTurnSnapshot, now: Date = .now) -> Bool {
        let startedSeconds = TimeInterval(snapshot.startedAtMs) / 1000.0
        return now.timeIntervalSince1970 - startedSeconds > staleAfter
    }
}
