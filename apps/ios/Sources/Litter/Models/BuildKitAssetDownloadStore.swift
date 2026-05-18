import Combine
import Foundation

struct BuildKitAssetDownloadConfig: Codable, Equatable, Sendable {
    var owner: String = "NightVibes33"
    var repo: String = "litter-buildkit-assets"
    var tag: String = "buildkit-ios26.4-v1"
    var assetName: String = "LitterBuildKitAssets.zip"
    var sha256: String = ""
    var directDownloadURL: String?

    var normalizedSHA256: String? {
        let trimmed = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    mutating func normalize() {
        owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        repo = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        assetName = assetName.trimmingCharacters(in: .whitespacesAndNewlines)
        sha256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        directDownloadURL = directDownloadURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if directDownloadURL?.isEmpty == true { directDownloadURL = nil }
    }
}

enum BuildKitAssetDownloadPhase: Equatable, Sendable {
    case idle
    case resolving
    case downloading
    case verifying
    case extracting
    case installing
    case ready
    case cancelled
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "Ready to download"
        case .resolving: return "Finding private release"
        case .downloading: return "Downloading asset pack"
        case .verifying: return "Verifying SHA256"
        case .extracting: return "Extracting BuildKit assets"
        case .installing: return "Installing BuildKit assets"
        case .ready: return "BuildKit assets installed"
        case .cancelled: return "Download cancelled"
        case .failed: return "Download failed"
        }
    }

    var isBusy: Bool {
        switch self {
        case .resolving, .downloading, .verifying, .extracting, .installing:
            return true
        default:
            return false
        }
    }
}

struct BuildKitGitHubReleaseAsset: Decodable, Equatable, Sendable {
    var name: String
    var url: URL
    var browserDownloadURL: URL?
    var size: Int64?

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

private struct BuildKitGitHubReleaseResponse: Decodable, Sendable {
    var assets: [BuildKitGitHubReleaseAsset]
}

enum BuildKitAssetDownloadError: LocalizedError, Equatable {
    case invalidConfig(String)
    case releaseHTTPStatus(Int)
    case assetHTTPStatus(Int)
    case assetNotFound(String)
    case invalidSHA256(String)
    case sha256SidecarMissing(String)
    case sha256Mismatch(expected: String, actual: String)
    case noDownloadDestination

    var errorDescription: String? {
        switch self {
        case .invalidConfig(let field):
            return "BuildKit asset config is missing: \(field)."
        case .releaseHTTPStatus(let code):
            return "GitHub release lookup failed with HTTP \(code)."
        case .assetHTTPStatus(let code):
            return "GitHub asset download failed with HTTP \(code)."
        case .assetNotFound(let name):
            return "GitHub release asset was not found: \(name)."
        case .invalidSHA256(let value):
            return "Invalid SHA256 value: \(value)."
        case .sha256SidecarMissing(let name):
            return "No SHA256 was configured and sidecar asset was missing: \(name)."
        case .sha256Mismatch(let expected, let actual):
            return "BuildKit asset SHA256 mismatch. Expected \(expected), got \(actual)."
        case .noDownloadDestination:
            return "No local download destination was prepared."
        }
    }
}

@MainActor
final class BuildKitAssetDownloadStore: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var config: BuildKitAssetDownloadConfig {
        didSet {
            guard config != oldValue else { return }
            saveConfig()
        }
    }
    @Published private(set) var phase: BuildKitAssetDownloadPhase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var totalBytes: Int64?
    @Published private(set) var bytesPerSecond: Double = 0
    @Published private(set) var lastOutput: String?
    @Published private(set) var hasStoredToken: Bool
    @Published private(set) var installRevision: Int = 0

    private static let configKey = "BuildKitAssetDownloadConfig.v1"
    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?
    private var downloadDestination: URL?
    private var downloadStartedAt: Date?
    private var workerTask: Task<Void, Never>?

    override init() {
        self.config = Self.loadConfig()
        self.hasStoredToken = BuildKitAssetTokenStore.shared.hasStoredToken
        super.init()
    }

    var phaseMessage: String {
        if case .failed(let message) = phase { return message }
        return phase.title
    }

    var progressText: String {
        if let totalBytes, totalBytes > 0 {
            return "\(Self.byteString(downloadedBytes)) / \(Self.byteString(totalBytes))"
        }
        if downloadedBytes > 0 { return Self.byteString(downloadedBytes) }
        return "Waiting"
    }

    var speedText: String {
        guard bytesPerSecond > 0 else { return "--" }
        return "\(Self.byteString(Int64(bytesPerSecond)))/s"
    }

    func saveToken(_ token: String) {
        do {
            try BuildKitAssetTokenStore.shared.save(token)
            hasStoredToken = true
            lastOutput = "GitHub release token saved to Keychain."
        } catch {
            phase = .failed(error.localizedDescription)
            lastOutput = error.localizedDescription
        }
    }

    func clearToken() {
        do {
            try BuildKitAssetTokenStore.shared.clear()
            hasStoredToken = false
            lastOutput = "GitHub release token cleared."
        } catch {
            phase = .failed(error.localizedDescription)
            lastOutput = error.localizedDescription
        }
    }

    func configure(from pack: AppUpdateToolchainPack) {
        var updated = config
        if let repository = pack.repository, let slash = repository.firstIndex(of: "/") {
            updated.owner = String(repository[..<slash])
            updated.repo = String(repository[repository.index(after: slash)...])
        }
        if let releaseTag = pack.releaseTag, !releaseTag.isEmpty {
            updated.tag = releaseTag
        }
        updated.assetName = pack.assetName
        updated.sha256 = pack.sha256
        updated.directDownloadURL = pack.downloadURL
        updated.normalize()
        config = updated
        saveConfig()
        lastOutput = "Selected toolchain pack: \(pack.displayName)"
    }

    func downloadAndInstall() {
        guard !phase.isBusy else { return }
        var normalized = config
        normalized.normalize()
        config = normalized
        saveConfig()
        progress = 0
        downloadedBytes = 0
        totalBytes = nil
        bytesPerSecond = 0
        lastOutput = nil
        workerTask = Task { [weak self] in
            await self?.runDownloadAndInstall()
        }
    }

    func cancel() {
        workerTask?.cancel()
        workerTask = nil
        downloadTask?.cancel()
        downloadTask = nil
        session?.invalidateAndCancel()
        session = nil
        if let continuation {
            continuation.resume(throwing: CancellationError())
            self.continuation = nil
        }
        phase = .cancelled
        lastOutput = "BuildKit asset download cancelled."
    }

    private func runDownloadAndInstall() async {
        do {
            try validateConfig(config)
            phase = .resolving
            let asset: BuildKitGitHubReleaseAsset
            let expectedSHA: String
            let downloadToken: String?
            if let directDownloadURL = config.directDownloadURL, !directDownloadURL.isEmpty {
                guard let url = URL(string: directDownloadURL) else {
                    throw BuildKitAssetDownloadError.invalidConfig("direct download URL")
                }
                guard let configured = config.normalizedSHA256 else {
                    throw BuildKitAssetDownloadError.invalidSHA256(config.sha256)
                }
                guard Self.isValidSHA256(configured) else { throw BuildKitAssetDownloadError.invalidSHA256(configured) }
                asset = BuildKitGitHubReleaseAsset(name: config.assetName, url: url, browserDownloadURL: url, size: nil)
                expectedSHA = configured
                downloadToken = nil
            } else {
                let requiredToken = try BuildKitAssetTokenStore.shared.load()
                let release = try await Self.fetchRelease(config: config, token: requiredToken)
                guard let releaseAsset = release.assets.first(where: { $0.name == config.assetName }) else {
                    throw BuildKitAssetDownloadError.assetNotFound(config.assetName)
                }
                asset = releaseAsset
                expectedSHA = try await expectedSHA256(config: config, release: release, token: requiredToken)
                downloadToken = requiredToken
            }
            let zipURL = try await download(asset: asset, token: downloadToken)

            phase = .verifying
            let actualSHA = try LitterBuildKit.fileSHA256Hex(zipURL)
            guard actualSHA.lowercased() == expectedSHA.lowercased() else {
                throw BuildKitAssetDownloadError.sha256Mismatch(expected: expectedSHA.lowercased(), actual: actualSHA.lowercased())
            }

            phase = .extracting
            phase = .installing
            let output = await LitterBuildKit.shared.importAssetZip(from: zipURL)
            lastOutput = output
            if output.lowercased().contains("failed") {
                phase = .failed(output)
            } else {
                phase = .ready
                installRevision += 1
            }
        } catch is CancellationError {
            phase = .cancelled
            lastOutput = "BuildKit asset download cancelled."
        } catch {
            let message = error.localizedDescription
            phase = .failed(message)
            lastOutput = message
        }
        cleanupDownloadState()
    }

    private func expectedSHA256(config: BuildKitAssetDownloadConfig, release: BuildKitGitHubReleaseResponse, token: String?) async throws -> String {
        if let configured = config.normalizedSHA256 {
            guard Self.isValidSHA256(configured) else { throw BuildKitAssetDownloadError.invalidSHA256(configured) }
            return configured
        }
        let sidecarName = "\(config.assetName).sha256"
        guard let sidecar = release.assets.first(where: { $0.name == sidecarName }) else {
            throw BuildKitAssetDownloadError.sha256SidecarMissing(sidecarName)
        }
        let text = try await Self.fetchReleaseAssetText(sidecar, token: token)
        let parsed = try Self.parseSHA256Sidecar(text)
        guard Self.isValidSHA256(parsed) else { throw BuildKitAssetDownloadError.invalidSHA256(parsed) }
        configSHA256(parsed)
        return parsed
    }

    private func configSHA256(_ sha: String) {
        var updated = config
        updated.sha256 = sha.lowercased()
        config = updated
    }

    private func download(asset: BuildKitGitHubReleaseAsset, token: String?) async throws -> URL {
        let destination = Self.temporaryDownloadURL(assetName: asset.name)
        downloadDestination = destination
        totalBytes = asset.size
        downloadStartedAt = Date()
        phase = .downloading

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            var request = Self.request(url: asset.url, token: token, accept: "application/octet-stream")
            request.timeoutInterval = 120
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 60 * 60
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.downloadTask(with: request)
            self.downloadTask = task
            task.resume()
        }
    }

    private func validateConfig(_ config: BuildKitAssetDownloadConfig) throws {
        if let directDownloadURL = config.directDownloadURL, !directDownloadURL.isEmpty {
            if URL(string: directDownloadURL) == nil { throw BuildKitAssetDownloadError.invalidConfig("direct download URL") }
            if config.assetName.isEmpty { throw BuildKitAssetDownloadError.invalidConfig("asset name") }
            if config.normalizedSHA256 == nil { throw BuildKitAssetDownloadError.invalidConfig("SHA256") }
            return
        }
        if config.owner.isEmpty { throw BuildKitAssetDownloadError.invalidConfig("owner") }
        if config.repo.isEmpty { throw BuildKitAssetDownloadError.invalidConfig("repo") }
        if config.tag.isEmpty { throw BuildKitAssetDownloadError.invalidConfig("tag") }
        if config.assetName.isEmpty { throw BuildKitAssetDownloadError.invalidConfig("asset name") }
    }

    private func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.configKey)
    }

    private static func loadConfig() -> BuildKitAssetDownloadConfig {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let decoded = try? JSONDecoder().decode(BuildKitAssetDownloadConfig.self, from: data) else {
            return BuildKitAssetDownloadConfig()
        }
        return decoded
    }

    private static func temporaryDownloadURL(assetName: String) -> URL {
        let cleanName = assetName.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LitterBuildKitDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(cleanName)
    }

    private func cleanupDownloadState() {
        workerTask = nil
        downloadTask = nil
        session?.finishTasksAndInvalidate()
        session = nil
        continuation = nil
        downloadDestination = nil
        downloadStartedAt = nil
    }

    private func completeDownload(task: URLSessionDownloadTask, location: URL) {
        guard let continuation else { return }
        self.continuation = nil
        do {
            if let response = task.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                throw BuildKitAssetDownloadError.assetHTTPStatus(response.statusCode)
            }
            guard let destination = downloadDestination else { throw BuildKitAssetDownloadError.noDownloadDestination }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation.resume(returning: destination)
        } catch {
            continuation.resume(throwing: error)
        }
    }

    private func completeDownload(error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }

    private func updateProgress(written: Int64, totalWritten: Int64, expected: Int64) {
        downloadedBytes = totalWritten
        if expected > 0 { totalBytes = expected }
        if let totalBytes, totalBytes > 0 {
            progress = min(max(Double(totalWritten) / Double(totalBytes), 0), 1)
        }
        if let started = downloadStartedAt {
            let elapsed = max(Date().timeIntervalSince(started), 0.1)
            bytesPerSecond = Double(totalWritten) / elapsed
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Task { @MainActor [weak self] in
            self?.completeDownload(task: downloadTask, location: location)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor [weak self] in
            self?.updateProgress(written: bytesWritten, totalWritten: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            if (error as NSError).code == NSURLErrorCancelled {
                self?.completeDownload(error: CancellationError())
            } else {
                self?.completeDownload(error: error)
            }
        }
    }

    static func parseSHA256Sidecar(_ text: String) throws -> String {
        let token = text
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .map(String.init)
            .first ?? ""
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidSHA256(normalized) else { throw BuildKitAssetDownloadError.invalidSHA256(token) }
        return normalized
    }

    private static func isValidSHA256(_ value: String) -> Bool {
        value.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil
    }

    private static func fetchRelease(config: BuildKitAssetDownloadConfig, token: String?) async throws -> BuildKitGitHubReleaseResponse {
        let path = "https://api.github.com/repos/\(config.owner)/\(config.repo)/releases/tags/\(config.tag)"
        guard let url = URL(string: path) else { throw BuildKitAssetDownloadError.invalidConfig("GitHub release URL") }
        let request = request(url: url, token: token, accept: "application/vnd.github+json")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw BuildKitAssetDownloadError.releaseHTTPStatus(response.statusCode)
        }
        return try JSONDecoder().decode(BuildKitGitHubReleaseResponse.self, from: data)
    }

    private static func fetchReleaseAssetText(_ asset: BuildKitGitHubReleaseAsset, token: String?) async throws -> String {
        let request = request(url: asset.url, token: token, accept: "application/octet-stream")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw BuildKitAssetDownloadError.assetHTTPStatus(response.statusCode)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func request(url: URL, token: String?, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Litter-BuildKit", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
