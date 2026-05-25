import Foundation
import Observation

struct UserMount: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let bookmarkData: Data
    let displayPath: String
    let addedAt: Date
}

enum MountStatus: Equatable {
    case mounted
    case resolutionFailed(String)
    case mountFailed(rc: Int32, message: String)
}

/// Live state for user-picked folders mounted into the iSH fakefs at `/mnt/<name>`.
///
/// Persistence is JSON in `UserDefaults`; runtime state is the set of currently
/// security-scope-held URLs. Scopes are acquired on add/boot and released only
/// on user removal (or process death), per Apple's balanced start/stop rule.
@MainActor
@Observable
final class UserMountStore {
    static let shared = UserMountStore()

    private(set) var mounts: [UserMount] = []
    private(set) var statuses: [UUID: MountStatus] = [:]

    @ObservationIgnored private var heldUrls: [UUID: URL] = [:]
    @ObservationIgnored private let storageKey = "litter.userMounts.v1"

    /// Rootfs top-level directories under `apps/ios/Resources/fs/data/` plus
    /// `apps` (already used by the existing `/mnt/apps` mount). A picked
    /// folder whose `lastPathComponent` matches one of these gets auto-suffixed.
    @ObservationIgnored private let reservedNames: Set<String> = [
        "apps", "bin", "dev", "etc", "home", "lib", "media", "mnt",
        "opt", "proc", "root", "run", "sbin", "srv", "sys", "tmp", "usr", "var",
    ]

    private init() {
        mounts = loadFromDefaults()
    }

    // MARK: - Lifecycle

    func loadAndRemountAll() async {
        for mount in mounts {
            await resolveAndMount(mount, isRetry: false)
        }
    }

    /// Pick a folder URL returned from `.fileImporter` and persist+mount it.
    ///
    /// The URL is expected to already be a security-scoped reference from the
    /// document picker. We persist a bookmark for relaunch and keep the scope
    /// held for the process lifetime.
    func addByPicking(url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            LLog.error("mount", "failed to start security scope for picked folder")
            return
        }
        let bookmarkData: Data
        do {
            bookmarkData = try url.bookmarkData()
        } catch {
            url.stopAccessingSecurityScopedResource()
            LLog.error("mount", "bookmarkData failed", error: error)
            return
        }
        let name = nextAvailableName(for: url.lastPathComponent)
        let mount = UserMount(
            id: UUID(),
            name: name,
            bookmarkData: bookmarkData,
            displayPath: url.path,
            addedAt: Date()
        )
        mounts.append(mount)
        heldUrls[mount.id] = url
        save()

        let rc = await runMount(name: name, hostPath: url.path)
        if rc == 0 {
            statuses[mount.id] = .mounted
        } else {
            statuses[mount.id] = .mountFailed(rc: rc, message: "mount -t real returned \(rc)")
        }
    }

    func remove(id: UUID) async {
        guard let index = mounts.firstIndex(where: { $0.id == id }) else { return }
        let mount = mounts[index]
        _ = await runUmount(name: mount.name)
        if let url = heldUrls.removeValue(forKey: id) {
            url.stopAccessingSecurityScopedResource()
        }
        statuses.removeValue(forKey: id)
        mounts.remove(at: index)
        save()
    }

    /// Replace a stale/broken mount's bookmark with a freshly picked URL.
    func reconnect(id: UUID, newUrl: URL) async {
        guard let index = mounts.firstIndex(where: { $0.id == id }) else { return }
        // Tear down any stale held scope for this record.
        if let oldUrl = heldUrls.removeValue(forKey: id) {
            _ = await runUmount(name: mounts[index].name)
            oldUrl.stopAccessingSecurityScopedResource()
        }
        guard newUrl.startAccessingSecurityScopedResource() else {
            LLog.error("mount", "reconnect: failed to start security scope")
            return
        }
        let bookmarkData: Data
        do {
            bookmarkData = try newUrl.bookmarkData()
        } catch {
            newUrl.stopAccessingSecurityScopedResource()
            LLog.error("mount", "reconnect: bookmarkData failed", error: error)
            return
        }
        let old = mounts[index]
        mounts[index] = UserMount(
            id: old.id,
            name: old.name,
            bookmarkData: bookmarkData,
            displayPath: newUrl.path,
            addedAt: old.addedAt
        )
        heldUrls[id] = newUrl
        save()

        let rc = await runMount(name: old.name, hostPath: newUrl.path)
        statuses[id] = (rc == 0)
            ? .mounted
            : .mountFailed(rc: rc, message: "mount -t real returned \(rc)")
    }

    // MARK: - Internals

    private func resolveAndMount(_ mount: UserMount, isRetry: Bool) async {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: mount.bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            statuses[mount.id] = .resolutionFailed(error.localizedDescription)
            LLog.warn(
                "mount",
                "bookmark resolve failed",
                fields: ["name": mount.name, "error": String(describing: error)]
            )
            return
        }

        if isStale {
            if let refreshed = try? url.bookmarkData(),
               let index = mounts.firstIndex(where: { $0.id == mount.id }) {
                mounts[index] = UserMount(
                    id: mount.id,
                    name: mount.name,
                    bookmarkData: refreshed,
                    displayPath: url.path,
                    addedAt: mount.addedAt
                )
                save()
            }
        }

        guard url.startAccessingSecurityScopedResource() else {
            statuses[mount.id] = .resolutionFailed("startAccessingSecurityScopedResource returned false")
            return
        }
        heldUrls[mount.id] = url

        let rc = await runMount(name: mount.name, hostPath: url.path)
        if rc == 0 {
            statuses[mount.id] = .mounted
        } else {
            statuses[mount.id] = .mountFailed(rc: rc, message: "mount -t real returned \(rc)")
        }
    }

    private func runMount(name: String, hostPath: String) async -> Int32 {
        let target = "/mnt/" + name
        let cmd = "mkdir -p \(IshFS.shellQuote(target)) && mount -t real \(IshFS.shellQuote(hostPath)) \(IshFS.shellQuote(target))"
        let result = await IshFS.run(cmd)
        if result.exitCode != 0 {
            LLog.warn(
                "mount",
                "mount -t real failed",
                fields: [
                    "name": name,
                    "rc": result.exitCode,
                    "output": result.output,
                ]
            )
        }
        return result.exitCode
    }

    private func runUmount(name: String) async -> Int32 {
        let target = "/mnt/" + name
        let cmd = "umount \(IshFS.shellQuote(target))"
        let result = await IshFS.run(cmd)
        return result.exitCode
    }

    private func nextAvailableName(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "folder" : trimmed
        let existing = Set(mounts.map(\.name))
        let isUsable: (String) -> Bool = { name in
            !existing.contains(name) && !self.reservedNames.contains(name.lowercased())
        }
        if isUsable(base) { return base }
        var counter = 2
        while true {
            let candidate = "\(base) (\(counter))"
            if isUsable(candidate) { return candidate }
            counter += 1
        }
    }

    // MARK: - Persistence

    private func loadFromDefaults() -> [UserMount] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([UserMount].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(mounts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
