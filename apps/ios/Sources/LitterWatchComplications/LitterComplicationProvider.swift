import Foundation
import WidgetKit

/// `AppIntentTimelineProvider` shared by all three complications. Resolves
/// the configured `ServerSelectionIntent.server`:
///
/// - `nil` → use the aggregate `complication.snapshot.v1` (legacy/default).
/// - non-nil → look up that server's slice in
///   `complication.per-server.v1` and fall back to the aggregate if the
///   selected server has no entry yet.
///
/// The legacy `TimelineProvider`-shape behavior (one entry now + 30 ticks
/// while running) is preserved unchanged.
struct LitterComplicationProvider: AppIntentTimelineProvider {
    typealias Intent = ServerSelectionIntent
    typealias Entry = LitterComplicationEntry

    func placeholder(in context: Context) -> LitterComplicationEntry {
        .placeholder
    }

    func snapshot(for configuration: ServerSelectionIntent, in context: Context) async -> LitterComplicationEntry {
        resolveCurrent(for: configuration)
    }

    func timeline(for configuration: ServerSelectionIntent, in context: Context) async -> Timeline<LitterComplicationEntry> {
        let base = resolveCurrent(for: configuration)
        return makeTimeline(base: base)
    }

    func recommendations() -> [AppIntentRecommendation<ServerSelectionIntent>] {
        []
    }

    // MARK: - Resolution

    private func resolveCurrent(for configuration: ServerSelectionIntent) -> LitterComplicationEntry {
        if let serverId = configuration.server?.id,
           let payload = perServerPayload(for: serverId) {
            return LitterComplicationStore.entry(from: payload)
        }
        return LitterComplicationStore.current()
    }

    private func perServerPayload(for serverId: String) -> LitterComplicationPayload? {
        let map = LitterPerServerComplicationStore.current()
        guard let data = map[serverId] else { return nil }
        return try? JSONDecoder().decode(LitterComplicationPayload.self, from: data)
    }

    // MARK: - Timeline shape

    private func makeTimeline(base: LitterComplicationEntry) -> Timeline<LitterComplicationEntry> {
        let now = Date()
        var entries: [LitterComplicationEntry] = []

        if base.mode == .running {
            // Tick once a minute for the next 30m. Each entry carries the same
            // start epoch so the view recomputes elapsed against `entry.date`.
            for step in 0..<30 {
                entries.append(
                    LitterComplicationEntry(
                        date: now.addingTimeInterval(TimeInterval(step) * 60),
                        mode: .running,
                        lastTurnStartMsEpoch: base.lastTurnStartMsEpoch,
                        taskId: base.taskId,
                        progress: min(1, base.progress + Double(step) * 0.01),
                        title: base.title,
                        toolLine: base.toolLine,
                        serverCount: base.serverCount
                    )
                )
            }
            return Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 30)))
        } else {
            entries.append(base)
            return Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 15)))
        }
    }
}
