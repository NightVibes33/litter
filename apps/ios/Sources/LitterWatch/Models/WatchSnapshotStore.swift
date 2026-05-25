import Foundation

/// Persists the most recent `WatchSnapshotPayload` into the watch app group.
/// Mirrors `LitterComplicationStore` so the watch app can show last-known state
/// on cold launch even when the phone is unreachable.
enum WatchSnapshotStore {
    static let appGroup = "group.com.sigkitten.litter"
    static let payloadKey = "watch.snapshot.v1"
    static let timestampKey = "watch.snapshot.v1.timestamp"

    /// Returns the persisted payload + timestamp written by iOS, or nil if
    /// no snapshot has ever been written.
    static func current() -> (WatchSnapshotPayload, Date)? {
        guard
            let defaults = UserDefaults(suiteName: appGroup),
            let data = defaults.data(forKey: payloadKey),
            let payload = try? JSONDecoder().decode(WatchSnapshotPayload.self, from: data)
        else { return nil }

        let raw = defaults.double(forKey: timestampKey)
        let date = raw > 0 ? Date(timeIntervalSince1970: raw) : Date()
        return (payload, date)
    }

    static func save(_ payload: WatchSnapshotPayload, date: Date = Date()) {
        guard
            let defaults = UserDefaults(suiteName: appGroup),
            let data = try? JSONEncoder().encode(payload)
        else { return }

        defaults.set(data, forKey: payloadKey)
        defaults.set(date.timeIntervalSince1970, forKey: timestampKey)
    }
}
