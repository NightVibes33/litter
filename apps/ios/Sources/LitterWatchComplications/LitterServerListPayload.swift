import Foundation

/// Codable wire-format for the `servers.v1` slice of the shared App Group.
/// Written by the iOS container (`WatchCompanionBridge`) any time the set
/// of connected servers changes, and read by the widget configuration
/// intent's `ServerEntityQuery` to populate the per-server picker.
///
/// Kept intentionally small: only the fields the watch face picker needs.
/// If a richer schema is ever needed, add a new versioned key
/// (`servers.v2`) and migrate consumers — never break the old shape.
struct LitterServerListPayload: Codable, Equatable {
    struct Server: Codable, Equatable, Hashable {
        let id: String
        let displayName: String
    }

    let servers: [Server]
}

/// Reads/writes the connected-server list out of the shared App Group.
enum LitterServerListStore {
    static let appGroup = "group.com.sigkitten.litter"
    static let key = "servers.v1"

    static func current() -> LitterServerListPayload? {
        guard
            let defaults = UserDefaults(suiteName: appGroup),
            let data = defaults.data(forKey: key)
        else { return nil }
        return try? JSONDecoder().decode(LitterServerListPayload.self, from: data)
    }

    static func write(_ payload: LitterServerListPayload) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Per-server complication snapshot map. The iOS container writes one entry
/// per known server in addition to the existing aggregate
/// `complication.snapshot.v1` write — the configuration intent uses these
/// to filter the running/needsApproval count down to a single server when
/// the user has picked one.
///
/// Shape matches the per-server `LitterComplicationEntry.Payload` written
/// in the aggregate path, so the same decoder can rehydrate either side.
enum LitterPerServerComplicationStore {
    static let appGroup = "group.com.sigkitten.litter"
    static let key = "complication.per-server.v1"

    /// Returns the per-server payload map, keyed by serverId.
    static func current() -> [String: Data] {
        guard
            let defaults = UserDefaults(suiteName: appGroup),
            let raw = defaults.dictionary(forKey: key)
        else { return [:] }
        var out: [String: Data] = [:]
        for (k, v) in raw {
            if let data = v as? Data {
                out[k] = data
            }
        }
        return out
    }

    static func write(_ map: [String: Data]) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.set(map, forKey: key)
    }
}
