import Foundation
import CryptoKit
import MetricKit

/// Synchronous file writes preserve the last completed log entry if the process exits.
/// Never install Swift signal handlers: allocating or taking locks there is unsafe.
final class DiagnosticsLogWriter: @unchecked Sendable {
    let directory: URL
    private let lock = NSLock()
    private let loggingQueue = DispatchQueue(label: "alleycat.diagnostics.file-writes", qos: .utility)
    private let maxBytes: Int
    private let maxFiles: Int
    private var file: URL?
    private var bytes = 0

    init(directory: URL, maxBytes: Int = 2 * 1024 * 1024, maxFiles: Int = 10) {
        self.directory = directory
        self.maxBytes = maxBytes
        self.maxFiles = maxFiles
    }

    // High-volume debug/info writes are dispatched to a serial utility queue.
    // Critical warnings/errors wait for preceding entries, preserving order.
    func appendPrepared(_ line: String, critical: Bool) {
        if critical {
            loggingQueue.sync { appendLine(line, alreadyRedacted: true) }
        } else {
            loggingQueue.async { [self] in appendLine(line, alreadyRedacted: true) }
        }
    }

    func drainDeferredWrites() {
        loggingQueue.sync {}
    }

    // Direct calls keep their previous synchronous, redacted semantics.
    func append(_ line: String) {
        appendLine(line, alreadyRedacted: false)
    }

    private func appendLine(_ line: String, alreadyRedacted: Bool) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeLine = alreadyRedacted ? line : LLog.redact(line)
            let bounded = String(safeLine.prefix(min(16_384, max(1, (maxBytes - 1) / 4)))) + "\n"
            let data = Data(bounded.utf8)
            if file == nil || bytes + data.count > maxBytes {
                let nextFile = directory.appendingPathComponent("session-\(UUID().uuidString).log")
                try Data().write(to: nextFile, options: .atomic)
                file = nextFile
                bytes = 0
                trimFiles(extension: "log", keeping: maxFiles)
            }
            guard let file else { return }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            bytes += data.count
        } catch {
            // Logging failure must not crash the app or recursively invoke LLog.
        }
    }

    func saveReport(_ data: Data, prefix: String, extension suffix: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let identity = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let url = directory.appendingPathComponent("\(prefix)-\(identity).\(suffix)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
            try data.write(to: url, options: .atomic)
            trimFiles(extension: suffix, keeping: maxFiles)
            return url
        } catch {
            return nil
        }
    }

    private func trimFiles(extension suffix: String, keeping count: Int) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        let ordered = files.filter { $0.pathExtension == suffix }.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return lhs > rhs
        }
        for file in ordered.dropFirst(max(1, count)) { try? FileManager.default.removeItem(at: file) }
    }
}

enum PersistentDiagnostics {
    static let writer = DiagnosticsLogWriter(directory:
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            .appendingPathComponent("Diagnostics", isDirectory: true)
    )

    /// Documents is exposed by UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace.
    static func prepareFilesAccess() {
        let guide = """
        Alley Cãt diagnostics
        Open Files → Browse → On My iPhone/iPad → Alley Cãt → Diagnostics.
        Session logs include debug events, lifecycle, runtime and action failures.
        Logs rotate at 2 MB, retaining 10 files. Previous sessions survive restart.
        Apple diagnostic reports appear when iOS delivers them; delivery is not immediate.
        Credentials are redacted. Review logs before sharing: IDs and file paths may remain.
        """
        do {
            try FileManager.default.createDirectory(at: writer.directory, withIntermediateDirectories: true)
            try guide.write(to: writer.directory.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        } catch {
            writer.append("Diagnostics directory setup failed: \(error.localizedDescription)")
        }
    }

    static func saveRecoveryBundle(_ text: String) -> URL? {
        writer.saveReport(Data(LLog.redact(text).utf8), prefix: "recovery", extension: "txt")
    }
}

/// iOS delivers diagnostic payloads asynchronously; reports are not guaranteed
/// immediately after a crash, and an ordinary OS termination may have no crash report.
final class AppleCrashDiagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = AppleCrashDiagnostics()

    func start() {
        MXMetricManager.shared.add(self)
        didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let report = LLog.redact(String(decoding: payload.jsonRepresentation(), as: UTF8.self))
            _ = PersistentDiagnostics.writer.saveReport(
                Data(report.utf8), prefix: "apple-diagnostic", extension: "json"
            )
        }
    }
}
