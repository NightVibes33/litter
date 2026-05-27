import Foundation
import SwiftUI
import UIKit

enum LitterPlatform {
#if targetEnvironment(macCatalyst)
    static let isCatalyst = true
#else
    static let isCatalyst = false
#endif

    /// `true` only on the unsandboxed Mac Catalyst lane (Developer ID
    /// notarized .dmg). Sandboxed Catalyst (Mac App Store) always sets
    /// `APP_SANDBOX_CONTAINER_ID`, so its absence on a Catalyst process
    /// is a reliable indicator that the App Sandbox is off and we can
    /// spawn child processes (codex app-server, etc.).
    static let isDirectDistMac: Bool = {
        guard isCatalyst else { return false }
        return ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil
    }()

    /// `true` whenever the process renders as a Mac app — Catalyst or
    /// "Designed for iPad" on Apple Silicon. AppKit-bridge bugs hit
    /// both modes (NSVisualEffectView ignoring `fractionComplete=0`,
    /// NavigationSplitView Liquid Glass material being clobbered by
    /// gradient backdrops, menu-equivalent shortcuts not firing in-view),
    /// so UI workarounds gate on this rather than the compile-time
    /// `targetEnvironment(macCatalyst)` flag — the iOS lane in
    /// "Designed for iPad" mode hits the same AppKit bridge.
    static let rendersAsMacApp: Bool = {
        if isCatalyst { return true }
        return ProcessInfo.processInfo.isiOSAppOnMac
    }()

    static let supportsLocalRuntime = !isCatalyst
    static let supportsVoiceRuntime = !isCatalyst

    private enum LocalRuntimeBootstrapState {
        case idle
        case starting
        case ready
    }

    private nonisolated(unsafe) static var bootstrapState: LocalRuntimeBootstrapState = .idle
    private static let bootstrapLock = NSLock()

    private static func finishLocalRuntimeBootstrap(_ state: LocalRuntimeBootstrapState) {
        bootstrapLock.lock()
        bootstrapState = state
        bootstrapLock.unlock()
    }

    static func bootstrapLocalRuntimeIfNeeded() {
#if !targetEnvironment(macCatalyst)
        Task.detached(priority: .utility) {
            do {
                try await LitterPlatform.ensureLocalRuntimeReady()
            } catch {
                NSLog("[ish] bootstrap/readiness failed: \(error.localizedDescription)")
            }
        }
#endif
    }

    static func repairLocalRuntimeBridgesIfNeeded() {
#if !targetEnvironment(macCatalyst)
        Task.detached(priority: .utility) {
            let codexBridge = await IshFS.repairCodexHomeBridge()
            if codexBridge.exitCode != 0 {
                let output = codexBridge.output.trimmingCharacters(in: .whitespacesAndNewlines)
                NSLog("[ish] /root/.codex bridge foreground repair failed rc=\(codexBridge.exitCode): \(output)")
            }
        }
#endif
    }

    static func ensureLocalRuntimeReady() async throws {
#if targetEnvironment(macCatalyst)
        return
#else
        try await LocalRuntimeReadinessCoordinator.shared.ensureReady()
#endif
    }

#if !targetEnvironment(macCatalyst)
    fileprivate static func performLocalRuntimeReadiness() async throws {
        migrateWorkDirIfHostPath()
        let fm = FileManager.default
        guard let bundleFs = Bundle.main.url(forResource: "fs", withExtension: nil) else {
            NSLog("[ish] bundled fs not found")
            throw LocalRuntimeReadinessError.bundledRootfsMissing
        }
        let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        guard let appSupport, let docs else {
            NSLog("[ish] could not resolve sandbox dirs")
            throw LocalRuntimeReadinessError.sandboxDirectoriesUnavailable
        }
        do {
            finishLocalRuntimeBootstrap(.starting)
            try ishBootstrap(
                bundleFsPath: bundleFs.path,
                applicationSupportDir: appSupport.path,
                documentsDir: docs.path
            )
            finishLocalRuntimeBootstrap(.ready)
            Task { @MainActor in
                await UserMountStore.shared.loadAndRemountAll()
            }
        } catch {
            if isAlreadyBootstrapped(error) {
                NSLog("[ish] bootstrap already completed")
                finishLocalRuntimeBootstrap(.ready)
                Task { @MainActor in
                    await UserMountStore.shared.loadAndRemountAll()
                }
            } else {
                finishLocalRuntimeBootstrap(.idle)
                throw error
            }
        }

        let codexBridge = await IshFS.repairCodexHomeBridgeOnReadyRuntime()
        if codexBridge.exitCode != 0 {
            let output = codexBridge.output.trimmingCharacters(in: .whitespacesAndNewlines)
            NSLog("[ish] /root/.codex bridge repair failed rc=\(codexBridge.exitCode): \(output)")
        }

        let preflight = ishRuntimePreflight()
        guard preflight.exitCode == 0 else {
            finishLocalRuntimeBootstrap(.idle)
            let rawOutput = String(data: preflight.output, encoding: .utf8) ?? ""
            let output = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? localShellDiagnostic(exitCode: preflight.exitCode)
                : rawOutput
            NSLog("[ish] preflight failed rc=\(preflight.exitCode): \(output)")
            throw LocalRuntimeReadinessError.preflightFailed(
                exitCode: preflight.exitCode,
                output: output
            )
        }

        await LitterBuildKit.shared.startFakefsRequestMonitor()
    }

    private static func isAlreadyBootstrapped(_ error: Error) -> Bool {
        for rendered in [String(reflecting: error), String(describing: error), error.localizedDescription] {
            let normalized = rendered.lowercased()
            if normalized.contains("alreadybootstrapped") || normalized.contains("already bootstrapped") {
                return true
            }
        }
        return false
    }

    private static func localShellDiagnostic(exitCode: Int32) -> String {
        exitCode == -6
            ? "iSH runtime is not bootstrapped; local shell is unavailable"
            : "local shell failed before producing output (exit code \(exitCode))"
    }
#endif

    /// iSH cannot see iOS sandbox paths. If the persisted `workDir` is one
    /// (carried over from an older build that ran shell commands directly in
    /// the iOS sandbox, or from the @AppStorage default), reset it to a
    /// fakefs-internal path so the model doesn't waste a cd-probe round-trip
    /// on every fresh turn.
    private static func migrateWorkDirIfHostPath() {
        let key = "workDir"
        let stored = UserDefaults.standard.string(forKey: key) ?? ""
        let hostPrefixes = ["/var/", "/private/", "/Users/", "/Library/", "/System/", "/Applications/"]
        let isHostPath = hostPrefixes.contains { stored.hasPrefix($0) }
        if stored.isEmpty || isHostPath {
            UserDefaults.standard.set("/root", forKey: key)
        }
    }

    static func defaultLocalWorkingDirectory() -> String {
#if targetEnvironment(macCatalyst)
        return NSHomeDirectory()
#else
        return ishDefaultCwd()
#endif
    }

    static func localRuntimeDisplayName() -> String {
#if targetEnvironment(macCatalyst)
        for candidate in [
            ProcessInfo.processInfo.hostName,
            ProcessInfo.processInfo.environment["HOSTNAME"],
            "Local Mac"
        ] {
            if let displayName = normalizedHostDisplayName(candidate) {
                return displayName
            }
        }
        return "Local Mac"
#else
        let device = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return device.isEmpty ? "This Device" : device
#endif
    }

#if targetEnvironment(macCatalyst)
    private static func normalizedHostDisplayName(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        if value.hasSuffix(".local") {
            value.removeLast(".local".count)
        } else if let dotIndex = value.firstIndex(of: ".") {
            value = String(value[..<dotIndex])
        }

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
#endif

    static func isRegularSurface(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        isCatalyst || horizontalSizeClass == .regular
    }
}

enum LocalRuntimeReadinessError: LocalizedError {
    case bundledRootfsMissing
    case sandboxDirectoriesUnavailable
    case preflightFailed(exitCode: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .bundledRootfsMissing:
            return "Local shell unavailable: bundled iSH filesystem is missing"
        case .sandboxDirectoriesUnavailable:
            return "Local shell unavailable: app sandbox directories are unavailable"
        case .preflightFailed(let exitCode, let output):
            if exitCode == -6 {
                return "Local shell unavailable: iSH runtime is not bootstrapped"
            }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Local shell unavailable: iSH preflight failed with exit code \(exitCode)"
            }
            return "Local shell unavailable: iSH preflight failed with exit code \(exitCode): \(trimmed)"
        }
    }
}

#if !targetEnvironment(macCatalyst)
private actor LocalRuntimeReadinessCoordinator {
    static let shared = LocalRuntimeReadinessCoordinator()

    private var readinessTask: Task<Void, Error>?

    func ensureReady() async throws {
        if let readinessTask {
            return try await readinessTask.value
        }

        let task = Task.detached(priority: .utility) {
            try await LitterPlatform.performLocalRuntimeReadiness()
        }
        readinessTask = task
        do {
            try await task.value
        } catch {
            readinessTask = nil
            throw error
        }
    }
}
#endif
