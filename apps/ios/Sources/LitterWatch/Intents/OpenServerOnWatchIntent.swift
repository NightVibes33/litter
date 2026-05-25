import AppIntents
import Foundation

/// AppIntent entity for one Codex server known to the watch. Built from
/// the most recent `WatchAppStore.tasks` push so the Shortcuts/Action
/// Button picker only offers servers the user actually has.
struct WatchServerEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Codex Server")
    static let defaultQuery = WatchServerEntityQuery()

    let id: String
    let displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

struct WatchServerEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [WatchServerEntity.ID]) async throws -> [WatchServerEntity] {
        let lookup = Dictionary(
            uniqueKeysWithValues: allServers().map { ($0.id, $0) }
        )
        return identifiers.compactMap { lookup[$0] }
    }

    @MainActor
    func suggestedEntities() async throws -> [WatchServerEntity] {
        allServers()
    }

    @MainActor
    private func allServers() -> [WatchServerEntity] {
        // Hydrate from the App Group so the picker has servers even when
        // the watch app hasn't been launched recently — the Shortcuts
        // resolver runs outside our main scene lifecycle.
        WatchAppStore.shared.hydrateFromAppGroupIfNeeded()
        let tasks = WatchAppStore.shared.tasks
        let pairs = tasks.map { ($0.serverId, $0.serverName) }
        let unique = Dictionary(pairs, uniquingKeysWith: { lhs, _ in lhs })
        return unique
            .map { WatchServerEntity(id: $0.key, displayName: $0.value) }
            .sorted { $0.displayName < $1.displayName }
    }
}

/// Opens the watch app on the home screen filtered to the picked server,
/// or — if there's a focused task on that server — drills directly into
/// it. Assignable to the Ultra Action Button via Settings → Action Button.
struct OpenServerOnWatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Server"
    static let description = IntentDescription(
        "Open the Litter watch app focused on a specific Codex server."
    )
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Server")
    var server: WatchServerEntity

    func perform() async throws -> some IntentResult {
        let url = URL(string: "litter-watch://server/\(server.id)")!
        await MainActor.run {
            WatchDeepLinkRouter.shared.handle(url)
        }
        return .result()
    }
}

/// Opens the watch app directly into the realtime voice screen.
/// Assignable to the Ultra Action Button.
struct StartVoiceOnWatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Voice"
    static let description = IntentDescription(
        "Open Litter and switch to the realtime voice screen."
    )
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let url = URL(string: "litter-watch://voice")!
        await MainActor.run {
            WatchDeepLinkRouter.shared.handle(url)
        }
        return .result()
    }
}
