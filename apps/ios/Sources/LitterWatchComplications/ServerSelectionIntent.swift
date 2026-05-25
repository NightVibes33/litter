import AppIntents
import Foundation

/// AppIntent entity that represents one Codex server known to the iOS
/// container app. Surfaced in the watch face's configuration sheet so the
/// user can pin a complication to a single server instead of seeing the
/// aggregate counts.
struct ServerEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Server")
    static let defaultQuery = ServerEntityQuery()

    let id: String
    let displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

/// Reads the connected-server list out of the App Group so the widget
/// configuration sheet can offer a real picker. When the App Group write
/// hasn't landed yet (cold install, before first phone sync) the query
/// returns an empty list — Apple's picker shows the `nil` fallback.
struct ServerEntityQuery: EntityQuery {
    func entities(for identifiers: [ServerEntity.ID]) async throws -> [ServerEntity] {
        let all = allServers()
        let lookup = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return identifiers.compactMap { lookup[$0] }
    }

    func suggestedEntities() async throws -> [ServerEntity] {
        allServers()
    }

    private func allServers() -> [ServerEntity] {
        guard let payload = LitterServerListStore.current() else { return [] }
        return payload.servers.map { ServerEntity(id: $0.id, displayName: $0.displayName) }
    }
}

/// `WidgetConfigurationIntent` driven from the watch face edit screen.
/// `server == nil` keeps the existing aggregate behavior (all servers).
struct ServerSelectionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Pick Server"
    static let description = IntentDescription(
        "Show a single server's task counts in this complication, or leave empty for all servers."
    )

    @Parameter(title: "Server")
    var server: ServerEntity?
}
