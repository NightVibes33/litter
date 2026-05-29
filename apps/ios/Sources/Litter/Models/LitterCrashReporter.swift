import Darwin
import Foundation
#if canImport(MetricKit)
import MetricKit
#endif
import UIKit

enum LitterCrashReporter {
    private nonisolated(unsafe) static var installed = false
    private nonisolated(unsafe) static var fatalSignalFD: CInt = -1
    private nonisolated(unsafe) static var previousExceptionHandler: NSUncaughtExceptionHandler?
    private static let reportsFolderName = "LitterCrashReports"
    private static let launchLogName = "last-launch.txt"
    private static let fatalSignalName = "fatal-signal-latest.txt"

    static func install() {
        guard !installed else { return }
        installed = true

        let directory = reportsDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        archivePreviousFatalSignalLog(in: directory)
        resetLaunchLog(in: directory)
        openFatalSignalLog(in: directory)
        installExceptionHandler()
        installSignalHandlers()
        installMetricKitSubscriber()
        mark("crash-reporter.install")
    }

    static func mark(_ event: String, file: StaticString = #fileID, line: UInt = #line) {
        if !installed {
            install()
        }

        let rendered = "\(timestamp()) \(event) \(file):\(line)\n"
        append(rendered, to: launchLogURL())
    }

    static func recordUncaughtException(_ exception: NSException) {
        let directory = reportsDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var lines: [String] = [
            "Litter uncaught Objective-C exception",
            "Recorded: \(timestamp())",
            "Name: \(exception.name.rawValue)",
            "Reason: \(exception.reason ?? "(none)")",
            "App: \(appIdentityLine())",
            "Device: \(deviceLine())",
            "",
            "Call stack:",
        ]
        lines.append(contentsOf: exception.callStackSymbols)
        appendRecentLaunchContext(to: &lines)

        let url = directory.appendingPathComponent("crash-exception-\(fileStamp()).txt")
        write(lines.joined(separator: "\n") + "\n", to: url)
    }

    static func recordFatalSignal(_ signalNumber: Int32) {
        let fd = fatalSignalFD
        guard fd >= 0 else { return }

        writeStatic("Litter fatal signal\n", to: fd)
        writeStatic("Signal: ", to: fd)
        writeStatic(signalName(signalNumber), to: fd)
        writeStatic("\nLast completed launch marks are in Documents/LitterCrashReports/last-launch.txt\n", to: fd)
    }

    #if canImport(MetricKit)
    static func recordMetricDiagnostics(_ payloads: [MXDiagnosticPayload], source: String) {
        guard !payloads.isEmpty else { return }

        let directory = reportsDirectory().appendingPathComponent("MetricKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, payload) in payloads.enumerated() {
            let url = directory.appendingPathComponent("metrickit-\(source)-\(fileStamp())-\(index).json")
            do {
                try payload.jsonRepresentation().write(to: url, options: .atomic)
            } catch {
                let fallbackURL = directory.appendingPathComponent("metrickit-\(source)-\(fileStamp())-\(index).txt")
                write("MetricKit payload write failed: \(error.localizedDescription)\n", to: fallbackURL)
            }
        }
    }
    #endif

    private static func installExceptionHandler() {
        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            LitterCrashReporter.recordUncaughtException(exception)
            LitterCrashReporter.previousExceptionHandler?(exception)
        }
    }

    private static func installSignalHandlers() {
        [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP].forEach { signalNumber in
            _ = Darwin.signal(signalNumber, litterFatalSignalHandler)
        }
    }

    private static func installMetricKitSubscriber() {
        #if canImport(MetricKit)
        if #available(iOS 14.0, *) {
            let manager = MXMetricManager.shared
            manager.add(LitterMetricKitSubscriber.shared)
            recordMetricDiagnostics(manager.pastDiagnosticPayloads, source: "past")
            mark("crash-reporter.metrickit-subscriber")
        }
        #endif
    }

    private static func reportsDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(reportsFolderName, isDirectory: true)
    }

    private static func launchLogURL() -> URL {
        reportsDirectory().appendingPathComponent(launchLogName)
    }

    private static func fatalSignalURL(in directory: URL? = nil) -> URL {
        (directory ?? reportsDirectory()).appendingPathComponent(fatalSignalName)
    }

    private static func resetLaunchLog(in directory: URL) {
        let text = [
            "Litter launch log",
            "Started: \(timestamp())",
            "App: \(appIdentityLine())",
            "Device: \(deviceLine())",
            "Reports folder: Documents/\(reportsFolderName)",
            ""
        ].joined(separator: "\n") + "\n"
        write(text, to: directory.appendingPathComponent(launchLogName))
    }

    private static func archivePreviousFatalSignalLog(in directory: URL) {
        let url = fatalSignalURL(in: directory)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0 else {
            return
        }

        let archived = directory.appendingPathComponent("crash-signal-\(fileStamp()).txt")
        try? FileManager.default.moveItem(at: url, to: archived)
    }

    private static func openFatalSignalLog(in directory: URL) {
        let url = fatalSignalURL(in: directory)
        write("Litter fatal signal scratch log\nStarted: \(timestamp())\n\n", to: url)
        fatalSignalFD = Darwin.open(url.path, O_WRONLY | O_APPEND | O_SYNC, S_IRUSR | S_IWUSR)
    }

    private static func appendRecentLaunchContext(to lines: inout [String]) {
        lines.append("")
        lines.append("Last launch marks:")
        if let text = try? String(contentsOf: launchLogURL(), encoding: .utf8), !text.isEmpty {
            lines.append(text)
        } else {
            lines.append("(missing)")
        }

        let recentLines = LLog.recentRedactedLines()
        guard !recentLines.isEmpty else { return }
        lines.append("")
        lines.append("Recent Litter logs:")
        lines.append(contentsOf: recentLines)
    }

    private static func append(_ text: String, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func write(_ text: String, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static func appIdentityLine() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let bundleID = Bundle.main.bundleIdentifier ?? "(unknown bundle)"
        let version = info["CFBundleShortVersionString"] as? String ?? "(unknown version)"
        let build = info["CFBundleVersion"] as? String ?? "(unknown build)"
        return "\(bundleID) \(version) (\(build))"
    }

    private static func deviceLine() -> String {
        let device = UIDevice.current
        return "\(device.model) iOS \(device.systemVersion)"
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func fileStamp() -> String {
        timestamp()
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    private static func signalName(_ signalNumber: Int32) -> StaticString {
        switch signalNumber {
        case SIGABRT:
            return "SIGABRT"
        case SIGSEGV:
            return "SIGSEGV"
        case SIGBUS:
            return "SIGBUS"
        case SIGILL:
            return "SIGILL"
        case SIGTRAP:
            return "SIGTRAP"
        default:
            return "UNKNOWN"
        }
    }

    private static func writeStatic(_ text: StaticString, to fd: CInt) {
        _ = Darwin.write(fd, text.utf8Start, text.utf8CodeUnitCount)
    }
}

private func litterFatalSignalHandler(_ signalNumber: Int32) {
    LitterCrashReporter.recordFatalSignal(signalNumber)
    _ = Darwin.signal(signalNumber, SIG_DFL)
    _ = Darwin.raise(signalNumber)
}

#if canImport(MetricKit)
private final class LitterMetricKitSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = LitterMetricKitSubscriber()

    func didReceive(_ payloads: [MXMetricPayload]) {}

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        LitterCrashReporter.recordMetricDiagnostics(payloads, source: "live")
    }
}
#endif
