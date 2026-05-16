import CryptoKit
import Foundation

struct GitHubReleaseAsset: Decodable, Equatable, Sendable {
    var id: Int64
    var name: String
    var browserDownloadURL: String
    var url: String
    var size: Int64?
    var digest: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case browserDownloadURL = "browser_download_url"
        case url
        case size
        case digest
    }
}

struct GitHubRelease: Decodable, Equatable, Sendable {
    var tagName: String
    var name: String?
    var htmlURL: String
    var body: String?
    var draft: Bool
    var prerelease: Bool
    var publishedAt: String?
    var assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case body
        case draft
        case prerelease
        case publishedAt = "published_at"
        case assets
    }

    func asset(named assetName: String) -> GitHubReleaseAsset? {
        assets.first { $0.name == assetName }
    }
}

enum GitHubReleaseAPI {
    static func releases(owner: String, repo: String, perPage: Int = 30, token: String? = nil) async throws -> [GitHubRelease] {
        let safePerPage = max(1, min(perPage, 100))
        let url = try makeURL("https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=\(safePerPage)")
        let data = try await data(url: url, token: token)
        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    static func release(owner: String, repo: String, tag: String, token: String? = nil) async throws -> GitHubRelease {
        let escapedTag = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        let url = try makeURL("https://api.github.com/repos/\(owner)/\(repo)/releases/tags/\(escapedTag)")
        let data = try await data(url: url, token: token)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    static func data(url: URL, token: String? = nil, accept: String = "application/vnd.github+json") async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Litter-iOS-Updater", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    static func request(url: URL, token: String? = nil, accept: String = "application/vnd.github+json") -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Litter-iOS-Updater", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func makeURL(_ string: String) throws -> URL {
        guard let url = URL(string: string) else {
            throw NSError(domain: "GitHubReleaseAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid GitHub URL."])
        }
        return url
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw NSError(domain: "GitHubReleaseAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub request failed (\(http.statusCode)): \(message)"])
        }
    }
}

final class FileDownloadDriver: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let progressHandler: (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var completedResult: Result<URL, Error>?

    init(destination: URL, progressHandler: @escaping (Int64, Int64) -> Void) {
        self.destination = destination
        self.progressHandler = progressHandler
    }

    func start(request: URLRequest) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let configuration = URLSessionConfiguration.default
                configuration.waitsForConnectivity = true
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 60 * 30
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.downloadTask(with: request)
                self.task = task
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progressHandler(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            try manager.moveItem(at: location, to: destination)
            completedResult = .success(destination)
        } catch {
            completedResult = .failure(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            continuation = nil
            self.task = nil
            self.session = nil
            session.finishTasksAndInvalidate()
        }

        if let error {
            continuation?.resume(throwing: error)
            return
        }

        switch completedResult {
        case .success(let url):
            continuation?.resume(returning: url)
        case .failure(let error):
            continuation?.resume(throwing: error)
        case .none:
            continuation?.resume(throwing: NSError(domain: "FileDownloadDriver", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download finished without a file."]))
        }
    }
}

enum LitterDownloadSupport {
    static func sha256Hex(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func normalizedSHA256(_ value: String?) -> String? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.lowercased().hasPrefix("sha256:") {
            text.removeFirst("sha256:".count)
        }
        if let first = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first {
            text = String(first)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdef")
        return text.count == 64 && text.unicodeScalars.allSatisfy { hexDigits.contains($0) } ? text : nil
    }

    static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if unit == 0 { return "\(Int(value)) \(units[unit])" }
        return String(format: "%.1f %@", value, units[unit])
    }

    static func appSupportDirectory(named name: String) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
