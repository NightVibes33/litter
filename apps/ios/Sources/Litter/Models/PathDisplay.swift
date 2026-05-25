import Foundation

/// Convert filesystem paths to short, user-facing strings.
///
/// For **local** codex paths, rewrites the app-container Documents home
/// and the app's `NSTemporaryDirectory()` to `~` and `/tmp` so the UI
/// shows `~/projects/foo` and `/tmp/x.txt` instead of
/// `/var/mobile/Containers/Data/Application/<UUID>/Documents/home/codex/...`.
///
/// For **remote** paths, delegates to the existing `abbreviateHomePath`
/// which shortens `/Users/<user>/<subpath>` and `/home/<user>/<subpath>`
/// to `~/<subpath>`.
enum PathDisplay {
    /// Callers pass `isLocal = true` only when `raw` is a path on the
    /// in-process iOS codex. Remote-server paths (SSH/WebSocket) go
    /// through `abbreviateHomePath`.
    static func display(_ raw: String, isLocal: Bool) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return isLocal ? "~" : trimmed }
        guard isLocal else { return remoteDisplay(trimmed) }
        let home = HomeAnchor.path
        if trimmed == home { return "~" }
        if trimmed.hasPrefix(home + "/") {
            return "~/" + trimmed.dropFirst(home.count + 1)
        }
        let tmp = realTmp()
        if !tmp.isEmpty {
            if trimmed == tmp { return "/tmp" }
            if trimmed.hasPrefix(tmp + "/") {
                return "/tmp/" + trimmed.dropFirst(tmp.count + 1)
            }
        }
        return trimmed
    }

    /// Inverse of `display`. Accepts user-entered display strings (`~/foo`,
    /// `/tmp/x`, or remote `~\foo`) and produces an absolute path for the
    /// selected host.
    static func expand(_ display: String, isLocal: Bool, remoteHome: String? = nil) -> String {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLocal else {
            return expandRemoteDisplay(trimmed, remoteHome: remoteHome)
        }
        if trimmed == "~" { return HomeAnchor.path }
        if trimmed.hasPrefix("~/") {
            return HomeAnchor.path + "/" + trimmed.dropFirst(2)
        }
        let tmp = realTmp()
        if !tmp.isEmpty {
            if trimmed == "/tmp" { return tmp }
            if trimmed.hasPrefix("/tmp/") {
                return tmp + "/" + trimmed.dropFirst(5)
            }
        }
        return trimmed
    }

    private static func realTmp() -> String {
        let raw = NSTemporaryDirectory()
        // Strip trailing slash so comparisons are uniform with prefix
        // matching that adds `/`.
        if raw.hasSuffix("/") { return String(raw.dropLast()) }
        return raw
    }

    private static func remoteDisplay(_ trimmed: String) -> String {
        let remote = RemotePath.parse(path: trimmed)
        guard remote.isWindows() else {
            return abbreviateHomePath(trimmed)
        }
        return abbreviateWindowsHome(remote) ?? remote.asString()
    }

    private static func expandRemoteDisplay(_ display: String, remoteHome: String?) -> String {
        guard let home = remoteHome?.trimmingCharacters(in: .whitespacesAndNewlines),
              !home.isEmpty else {
            return display
        }
        let remoteHomePath = RemotePath.parse(path: home)
        let normalizedHome = remoteHomePath.asString()
        if remoteHomePath.isWindows() {
            guard display == "~" || display.hasPrefix("~\\") || display.hasPrefix("~/") else {
                return display
            }
            if display == "~" { return normalizedHome }
            let suffix = String(display.dropFirst(2)).replacingOccurrences(of: "/", with: "\\")
            return appendWindowsSuffix(suffix, to: normalizedHome)
        }
        guard display == "~" || display.hasPrefix("~/") else {
            return display
        }
        if display == "~" { return normalizedHome }
        let suffix = String(display.dropFirst(2))
        return normalizedHome.hasSuffix("/") ? normalizedHome + suffix : normalizedHome + "/" + suffix
    }

    private static func appendWindowsSuffix(_ suffix: String, to home: String) -> String {
        let trimmedHome = home.hasSuffix("\\") ? String(home.dropLast()) : home
        guard !suffix.isEmpty else { return trimmedHome }
        return trimmedHome + "\\" + suffix
    }

    private static func abbreviateWindowsHome(_ remote: RemotePath) -> String? {
        let segments = remote.segments()
        guard segments.count >= 3 else { return nil }
        guard segments[1].label.caseInsensitiveCompare("Users") == .orderedSame else {
            return nil
        }
        let remainder = segments.dropFirst(3).map(\.label)
        guard !remainder.isEmpty else { return "~" }
        return "~\\" + remainder.joined(separator: "\\")
    }
}
