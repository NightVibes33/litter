import Combine
import Foundation
import UIKit

struct AppVersion: Comparable, Equatable, Sendable {
    var components: [Int]
    var build: Int

    init?(version: String, build: String) {
        let versionParts = version.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard (2...4).contains(versionParts.count) else { return nil }
        let parsed = versionParts.compactMap { Int($0) }
        guard parsed.count == versionParts.count, let buildNumber = Int(build.trimmingCharacters(in: .whitespacesAndNewlines)), buildNumber >= 0 else {
            return nil
        }
        self.components = parsed
        self.build = buildNumber
    }

    static var installed: AppVersion {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return AppVersion(version: version, build: build) ?? AppVersion(components: [0, 0, 0], build: 0)
    }

    var versionString: String {
        components.map(String.init).joined(separator: ".")
    }

    var displayString: String {
        "v\(build)"
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.build != rhs.build { return lhs.build < rhs.build }
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    private init(components: [Int], build: Int) {
        self.components = components
        self.build = build
    }
}

struct AppUpdateManifest: Codable, Equatable, Sendable {
    var schemaVersion: Int?
    var name: String?
    var bundleIdentifier: String
    var version: String
    var build: String
    var publicVersion: String?
    var commit: String?
    var buildMode: String?
    var minimumIOSVersion: String?
    var ipaAssetName: String
    var ipaDownloadURL: String
    var sha256: String
    var size: Int64?
    var publishedAt: String?
    var releaseNotes: String?
    var releaseURL: String?
    var sideStoreSourceURL: String?
    var altStoreSourceURL: String?

    var appVersion: AppVersion? {
        AppVersion(version: version, build: build)
    }

    var displayVersion: String {
        if let publicVersion, !publicVersion.isEmpty { return publicVersion }
        return appVersion?.displayString ?? "v\(build)"
    }

    var normalizedSHA256: String? {
        LitterDownloadSupport.normalizedSHA256(sha256)
    }
}

enum AppUpdateAvailability: Equatable {
    case unknown
    case available
    case upToDate
    case remoteOlder
    case incompatibleIOS(String)
    case incomparable(String)
    case noCompatibleRelease

    var title: String {
        switch self {
        case .unknown: return "Not checked"
        case .available: return "Update available"
        case .upToDate: return "Up to date"
        case .remoteOlder: return "Installed build is newer"
        case .incompatibleIOS: return "Update requires newer iOS"
        case .incomparable: return "Manual check needed"
        case .noCompatibleRelease: return "No compatible release"
        }
    }

    var allowsDownload: Bool {
        if case .available = self { return true }
        return false
    }
}

enum AppUpdatePhase: Equatable {
    case idle
    case checking
    case ready
    case downloading
    case verifying
    case downloaded
    case failed
    case cancelled

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .verifying: return true
        default: return false
        }
    }
}

@MainActor
final class AppUpdateStore: ObservableObject {
    @Published private(set) var installedVersion = AppVersion.installed
    @Published private(set) var latestManifest: AppUpdateManifest?
    @Published private(set) var latestRelease: GitHubRelease?
    @Published private(set) var availability: AppUpdateAvailability = .unknown
    @Published private(set) var phase: AppUpdatePhase = .idle
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var progressText = "No download running"
    @Published private(set) var speedText = ""
    @Published private(set) var checksumText = "Not verified"
    @Published private(set) var downloadedIPAURL: URL?
    @Published private(set) var lastError: String?
    @Published private(set) var statusMessage = "Check the app source for a newer sideload build."

    let owner = "NightVibes33"
    let repo = "litter"
    let manifestAssetName = "litter-update.json"
    let stableUpdateURL = "https://github.com/NightVibes33/litter/releases/download/app-source/litter-update.json"
    let stableSourceURL = "https://github.com/NightVibes33/litter/releases/download/app-source/litter-altstore-source.json"

    private var activeDriver: FileDownloadDriver?
    private var activeTask: Task<Void, Never>?
    private var downloadStartedAt: Date?

    var canDownload: Bool {
        availability.allowsDownload && !phase.isBusy
    }

    var canInstallDownloadedIPA: Bool {
        downloadedIPAURL != nil && checksumText.hasPrefix("Verified")
    }

    var releaseURL: URL? {
        if let releaseURL = latestManifest?.releaseURL, let url = URL(string: releaseURL) { return url }
        if let htmlURL = latestRelease?.htmlURL, let url = URL(string: htmlURL) { return url }
        return URL(string: "https://github.com/\(owner)/\(repo)/releases")
    }

    var remoteIPAURL: URL? {
        guard let value = latestManifest?.ipaDownloadURL else { return nil }
        return URL(string: value)
    }

    var sideStoreInstallURL: URL? {
        installerURL(scheme: "sidestore", host: "install", targetURL: latestManifest?.ipaDownloadURL)
    }

    var altStoreInstallURL: URL? {
        installerURL(scheme: "altstore", host: "install", targetURL: latestManifest?.ipaDownloadURL)
    }

    var sideStoreSourceURL: URL? {
        installerURL(scheme: "sidestore", host: "source", targetURL: latestManifest?.sideStoreSourceURL ?? stableSourceURL)
    }

    var altStoreSourceURL: URL? {
        installerURL(scheme: "altstore", host: "source", targetURL: latestManifest?.altStoreSourceURL ?? stableSourceURL)
    }

    func refreshInstalledVersion() {
        installedVersion = AppVersion.installed
    }

    func checkForUpdates() async {
        guard !phase.isBusy else { return }
        refreshInstalledVersion()
        phase = .checking
        availability = .unknown
        latestManifest = nil
        latestRelease = nil
        downloadedIPAURL = nil
        downloadProgress = 0
        checksumText = "Not verified"
        progressText = "No download running"
        speedText = ""
        lastError = nil
        statusMessage = "Checking app source"

        do {
            let candidate = try await stableCandidate()
            latestManifest = candidate.manifest
            latestRelease = candidate.release
            availability = evaluate(candidate.manifest)
            statusMessage = statusMessage(for: availability, manifest: candidate.manifest)
            phase = .ready
        } catch {
            let stableError = error
            do {
                statusMessage = "Checking GitHub Releases fallback"
                let releases = try await GitHubReleaseAPI.releases(owner: owner, repo: repo, perPage: 30)
                let candidate = try await selectBestCandidate(from: releases)
                guard let candidate else {
                    availability = .noCompatibleRelease
                    statusMessage = "No release with \(manifestAssetName) was found."
                    lastError = "Stable app source failed: \(stableError.localizedDescription)"
                    phase = .ready
                    return
                }

                latestManifest = candidate.manifest
                latestRelease = candidate.release
                availability = evaluate(candidate.manifest)
                statusMessage = statusMessage(for: availability, manifest: candidate.manifest)
                phase = .ready
            } catch {
                phase = .failed
                availability = .unknown
                lastError = "Stable app source failed: \(stableError.localizedDescription)\nGitHub Releases fallback failed: \(error.localizedDescription)"
                statusMessage = "Update check failed."
            }
        }
    }

    func downloadUpdate() {
        guard activeTask == nil else { return }
        activeTask = Task { [weak self] in
            await self?.downloadUpdateAsync()
            await MainActor.run { self?.activeTask = nil }
        }
    }

    func cancelDownload() {
        activeTask?.cancel()
        activeTask = nil
        activeDriver?.cancel()
        activeDriver = nil
        phase = .cancelled
        progressText = "Download cancelled"
        speedText = ""
    }

    func removeDownloadedIPA() {
        guard let downloadedIPAURL else { return }
        try? FileManager.default.removeItem(at: downloadedIPAURL)
        self.downloadedIPAURL = nil
        downloadProgress = 0
        checksumText = "Not verified"
        progressText = "Removed downloaded IPA"
        phase = .ready
    }

    private func downloadUpdateAsync() async {
        guard let manifest = latestManifest, let remoteURL = URL(string: manifest.ipaDownloadURL) else {
            lastError = "No IPA download URL is available."
            return
        }
        guard let expectedSHA = manifest.normalizedSHA256 else {
            lastError = "Release metadata is missing a valid SHA-256 checksum."
            checksumText = "Missing checksum"
            return
        }

        do {
            phase = .downloading
            downloadProgress = 0
            downloadStartedAt = Date()
            checksumText = "Not verified"
            lastError = nil
            progressText = "Starting download"
            speedText = ""
            let directory = try LitterDownloadSupport.appSupportDirectory(named: "AppUpdates")
            try cleanupOldIPAs(in: directory, keeping: manifest.ipaAssetName)
            let destination = directory.appendingPathComponent(manifest.ipaAssetName)
            let request = GitHubReleaseAPI.request(url: remoteURL, accept: "application/octet-stream")
            let driver = FileDownloadDriver(destination: destination) { [weak self] written, expected in
                Task { @MainActor in self?.updateProgress(written: written, expected: expected) }
            }
            activeDriver = driver
            let fileURL = try await driver.start(request: request)
            activeDriver = nil

            phase = .verifying
            progressText = "Verifying SHA-256"
            let actualSHA = try LitterDownloadSupport.sha256Hex(for: fileURL)
            guard actualSHA == expectedSHA else {
                try? FileManager.default.removeItem(at: fileURL)
                checksumText = "Checksum mismatch"
                throw NSError(domain: "AppUpdateStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "SHA-256 mismatch. Expected \(expectedSHA), got \(actualSHA)."])
            }

            downloadedIPAURL = fileURL
            checksumText = "Verified \(actualSHA.prefix(12))"
            downloadProgress = 1
            progressText = "Downloaded \(manifest.ipaAssetName)"
            speedText = ""
            phase = .downloaded
        } catch is CancellationError {
            phase = .cancelled
            progressText = "Download cancelled"
            speedText = ""
        } catch {
            phase = .failed
            lastError = error.localizedDescription
            progressText = "Download failed"
            speedText = ""
        }
    }

    private struct Candidate {
        var release: GitHubRelease?
        var manifest: AppUpdateManifest
        var version: AppVersion?
    }

    private func stableCandidate() async throws -> Candidate {
        guard let manifestURL = URL(string: stableUpdateURL) else {
            throw NSError(domain: "AppUpdateStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid stable update feed URL."])
        }
        let data = try await GitHubReleaseAPI.data(url: manifestURL)
        var manifest = try JSONDecoder().decode(AppUpdateManifest.self, from: data)
        enrichStable(&manifest)
        return Candidate(release: nil, manifest: manifest, version: manifest.appVersion)
    }

    private func selectBestCandidate(from releases: [GitHubRelease]) async throws -> Candidate? {
        var best: Candidate?
        var firstIncomparable: Candidate?

        for release in releases where !release.draft {
            guard publicBuildNumber(from: release) != nil else { continue }
            guard let manifestAsset = release.asset(named: manifestAssetName), let manifestURL = URL(string: manifestAsset.browserDownloadURL) else {
                continue
            }
            do {
                let data = try await GitHubReleaseAPI.data(url: manifestURL)
                var manifest = try JSONDecoder().decode(AppUpdateManifest.self, from: data)
                enrich(&manifest, using: release)
                let candidate = Candidate(release: release, manifest: manifest, version: manifest.appVersion)
                guard let version = candidate.version else {
                    if firstIncomparable == nil { firstIncomparable = candidate }
                    continue
                }
                if best == nil || (best?.version.map { $0 < version } ?? true) {
                    best = candidate
                }
            } catch {
                if firstIncomparable == nil {
                    continue
                }
            }
        }

        return best ?? firstIncomparable
    }

    private func publicBuildNumber(from release: GitHubRelease) -> Int? {
        let values = [release.tagName, release.name ?? ""]
        for rawValue in values {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            for prefix in ["litter-v", "litter v", "litter-"] {
                guard value.hasPrefix(prefix) else { continue }
                let suffix = value.dropFirst(prefix.count)
                let digits = suffix.prefix { $0.isNumber }
                if let number = Int(digits), number > 0 { return number }
            }
        }
        return nil
    }

    private func enrich(_ manifest: inout AppUpdateManifest, using release: GitHubRelease) {
        if manifest.releaseURL?.isEmpty != false {
            manifest.releaseURL = release.htmlURL
        }
        if manifest.releaseNotes?.isEmpty != false {
            manifest.releaseNotes = release.body
        }
        if manifest.publishedAt?.isEmpty != false {
            manifest.publishedAt = release.publishedAt
        }
        if manifest.ipaDownloadURL.isEmpty, let ipaAsset = release.asset(named: manifest.ipaAssetName) {
            manifest.ipaDownloadURL = ipaAsset.browserDownloadURL
            if manifest.size == nil { manifest.size = ipaAsset.size }
            if manifest.sha256.isEmpty, let digest = ipaAsset.digest {
                manifest.sha256 = digest
            }
        }
        enrichStable(&manifest)
    }

    private func enrichStable(_ manifest: inout AppUpdateManifest) {
        if manifest.releaseURL?.isEmpty != false {
            manifest.releaseURL = "https://github.com/\(owner)/\(repo)/releases/tag/litter-v\(manifest.build)"
        }
        if manifest.sideStoreSourceURL?.isEmpty != false {
            manifest.sideStoreSourceURL = stableSourceURL
        }
        if manifest.altStoreSourceURL?.isEmpty != false {
            manifest.altStoreSourceURL = stableSourceURL
        }
    }

    private func evaluate(_ manifest: AppUpdateManifest) -> AppUpdateAvailability {
        guard let remoteVersion = manifest.appVersion else {
            return .incomparable("The release version or build is not numeric.")
        }
        if let minimum = manifest.minimumIOSVersion,
           let requiredOS = AppVersion(version: minimum, build: "0"),
           let currentOS = AppVersion(version: UIDevice.current.systemVersion, build: "0"),
           currentOS < requiredOS {
            return .incompatibleIOS(minimum)
        }
        if installedVersion < remoteVersion { return .available }
        if installedVersion == remoteVersion { return .upToDate }
        return .remoteOlder
    }

    private func statusMessage(for availability: AppUpdateAvailability, manifest: AppUpdateManifest) -> String {
        switch availability {
        case .unknown:
            return "Check the app source for a newer sideload build."
        case .available:
            return "Litter \(manifest.displayVersion) is available."
        case .upToDate:
            return "This install matches the latest app source release."
        case .remoteOlder:
            return "This install is newer than the latest app source release."
        case .incompatibleIOS(let version):
            return "The latest release requires iOS \(version) or newer."
        case .incomparable(let reason):
            return reason
        case .noCompatibleRelease:
            return "No compatible update metadata was found."
        }
    }

    private func updateProgress(written: Int64, expected: Int64) {
        if expected > 0 {
            downloadProgress = min(max(Double(written) / Double(expected), 0), 1)
            progressText = "\(LitterDownloadSupport.formatBytes(written)) / \(LitterDownloadSupport.formatBytes(expected))"
        } else {
            downloadProgress = 0
            progressText = LitterDownloadSupport.formatBytes(written)
        }
        if let downloadStartedAt {
            let elapsed = max(Date().timeIntervalSince(downloadStartedAt), 0.1)
            let bytesPerSecond = Int64(Double(written) / elapsed)
            speedText = "\(LitterDownloadSupport.formatBytes(bytesPerSecond))/s"
        }
    }

    private func cleanupOldIPAs(in directory: URL, keeping fileName: String) throws {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in contents where url.pathExtension.lowercased() == "ipa" && url.lastPathComponent != fileName {
            try? manager.removeItem(at: url)
        }
    }

    private func installerURL(scheme: String, host: String, targetURL: String?) -> URL? {
        guard let targetURL, !targetURL.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "url", value: targetURL)]
        return components.url
    }
}
