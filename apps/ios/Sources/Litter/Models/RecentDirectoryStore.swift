import Foundation

struct RecentDirectoryEntry: Codable, Identifiable, Hashable {
    let serverId: String
    let path: String
    let lastUsedAt: Date
    let useCount: Int

    var id: String {
        "\(serverId)|\(path)"
    }
}

@MainActor
final class RecentDirectoryStore {
    static let shared = RecentDirectoryStore()

    private let userDefaults: UserDefaults
    private let storageKey = "recent_directories_v1"
    private let maxEntriesPerServer = 20
    private let pickerDisplayLimit = 3

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func recentDirectories(for serverId: String, limit: Int? = nil) -> [RecentDirectoryEntry] {
        let normalizedServerId = serverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedServerId.isEmpty else { return [] }
        return loadAll()
            .filter { $0.serverId == normalizedServerId }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
            .prefix(limit ?? pickerDisplayLimit)
            .map { $0 }
    }

    @discardableResult
    func record(
        path: String,
        for serverId: String,
        at date: Date = Date(),
        incrementUseCount: Bool = true,
        limit: Int? = nil
    ) -> [RecentDirectoryEntry] {
        let normalizedServerId = serverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedServerId.isEmpty else { return [] }
        let normalizedPath = normalizePath(path)
        guard !normalizedPath.isEmpty else { return recentDirectories(for: normalizedServerId, limit: limit) }

        var all = loadAll()

        if let index = all.firstIndex(where: { $0.serverId == normalizedServerId && $0.path == normalizedPath }) {
            let existing = all[index]
            all[index] = RecentDirectoryEntry(
                serverId: normalizedServerId,
                path: normalizedPath,
                lastUsedAt: max(existing.lastUsedAt, date),
                useCount: incrementUseCount ? (existing.useCount + 1) : existing.useCount
            )
        } else {
            all.append(
                RecentDirectoryEntry(
                    serverId: normalizedServerId,
                    path: normalizedPath,
                    lastUsedAt: date,
                    useCount: incrementUseCount ? 1 : 0
                )
            )
        }

        all = trimEntries(all)
        saveAll(all)
        return recentDirectories(for: normalizedServerId, limit: limit)
    }

    @discardableResult
    func mergeSessionDirectories(_ entries: [RecentDirectoryEntry], for serverId: String) -> [RecentDirectoryEntry] {
        let normalizedServerId = serverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedServerId.isEmpty else { return [] }

        var merged = loadAll()
        for entry in entries where entry.serverId == normalizedServerId {
            let normalizedPath = normalizePath(entry.path)
            guard !normalizedPath.isEmpty else { continue }
            if let index = merged.firstIndex(where: { $0.serverId == normalizedServerId && $0.path == normalizedPath }) {
                let existing = merged[index]
                merged[index] = RecentDirectoryEntry(
                    serverId: normalizedServerId,
                    path: normalizedPath,
                    lastUsedAt: max(existing.lastUsedAt, entry.lastUsedAt),
                    useCount: max(existing.useCount, entry.useCount)
                )
            } else {
                merged.append(
                    RecentDirectoryEntry(
                        serverId: normalizedServerId,
                        path: normalizedPath,
                        lastUsedAt: entry.lastUsedAt,
                        useCount: entry.useCount
                    )
                )
            }
        }

        merged = trimEntries(merged)
        saveAll(merged)
        return recentDirectories(for: normalizedServerId)
    }

    @discardableResult
    func remove(path: String, for serverId: String, limit: Int? = nil) -> [RecentDirectoryEntry] {
        let normalizedServerId = serverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedServerId.isEmpty else { return [] }
        let normalizedPath = normalizePath(path)
        var all = loadAll()
        all.removeAll { $0.serverId == normalizedServerId && $0.path == normalizedPath }
        saveAll(all)
        return recentDirectories(for: normalizedServerId, limit: limit)
    }

    @discardableResult
    func clear(for serverId: String, limit _: Int? = nil) -> [RecentDirectoryEntry] {
        let normalizedServerId = serverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedServerId.isEmpty else { return [] }
        var all = loadAll()
        all.removeAll { $0.serverId == normalizedServerId }
        saveAll(all)
        return []
    }

    private func loadAll() -> [RecentDirectoryEntry] {
        guard let data = userDefaults.data(forKey: storageKey) else { return [] }
        do {
            return try JSONDecoder().decode([RecentDirectoryEntry].self, from: data)
        } catch {
            return []
        }
    }

    private func saveAll(_ entries: [RecentDirectoryEntry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            userDefaults.set(data, forKey: storageKey)
        } catch {}
    }

    private func trimEntries(_ entries: [RecentDirectoryEntry]) -> [RecentDirectoryEntry] {
        var grouped: [String: [RecentDirectoryEntry]] = [:]
        for entry in entries {
            grouped[entry.serverId, default: []].append(entry)
        }

        var trimmed: [RecentDirectoryEntry] = []
        for (_, serverEntries) in grouped {
            let sorted = serverEntries.sorted { $0.lastUsedAt > $1.lastUsedAt }
            trimmed.append(contentsOf: sorted.prefix(maxEntriesPerServer))
        }
        return trimmed
    }

    private func normalizePath(_ path: String) -> String {
        var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return "" }
        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}
