import CryptoKit
import Darwin
import Foundation

struct BuildKitAssetManifest: Codable, Equatable, Sendable {
    struct Toolchain: Codable, Equatable, Sendable {
        var name: String
        var coreCompilerFramework: String
        var nativeDriverFramework: String?
        var supportLibraries: String
        var sdkPath: String
    }

    var schemaVersion: Int
    var bundleIdentifier: String
    var createdAt: String?
    var sdkVersion: String
    var swiftVersion: String?
    var minimumIOS: String?
    var toolchain: Toolchain
    var capabilities: [String]
    var requiredPaths: [String]
    var sha256: [String: String]?
}

struct LitterBuildKitStatus: Equatable, Sendable {
    var sourceImportAvailable: Bool
    var privateAssetsInstalled: Bool
    var nativeCompilerAssetsInstalled: Bool
    var nativeDriverInstalled: Bool
    var nativeDriverLoadable: Bool
    var supportLibrariesInstalled: Bool
    var sdkInstalled: Bool
    var commandShimsInstalled: Bool
    var requestMonitorRunning: Bool
    var toolchainRoot: String
    var sdkRoot: String
    var buildKitRoot: String
    var commands: [String]
    var assetManifest: BuildKitAssetManifest?

    var isReadyForNativeBuilds: Bool {
        nativeCompilerAssetsInstalled && nativeDriverLoadable && supportLibrariesInstalled && sdkInstalled
    }

    var readinessTitle: String {
        if isReadyForNativeBuilds { return "On-device Swift builder ready" }
        if privateAssetsInstalled { return "Private BuildKit assets installed" }
        if sourceImportAvailable { return "Nyxian source imported" }
        return "BuildKit source missing"
    }

    var readinessDetail: String {
        if isReadyForNativeBuilds {
            return "Fakefs Swift and IPA commands can route to the native BuildKit driver."
        }
        if privateAssetsInstalled {
            return "The private asset pack is installed, but the native driver/framework is not loadable yet. Rebuild the sideload IPA with the private BuildKit framework embedded."
        }
        if sourceImportAvailable {
            return "The Nyxian source import is present. Install a private LitterBuildKitAssets bundle containing CoreCompiler, Swift support libraries, and iPhoneOS SDK assets to enable real local builds."
        }
        return "ThirdParty/Nyxian is missing from this build."
    }
}

actor LitterBuildKit {
    static let shared = LitterBuildKit()

    private static let requestRoot = "/root/.litter-buildkit/requests"
    private static let buildRoot = "/root/builds"
    private static let shimInstallMarker = "/root/.litter-buildkit/shims-installed-v2"
    private static let commandNames = [
        "litter-buildkit",
        "litter-buildkit-install-assets",
        "litter-fs-doctor",
        "litter-swift-check",
        "litter-swift-build",
        "litter-swift-test",
        "litter-ipa-build",
        "litter-ipa-package",
        "litter-build-status",
        "litter-build-cancel"
    ]

    private var monitorTask: Task<Void, Never>?
    private var activeJobs: [String: Task<BuildKitCommandResult, Never>] = [:]

    private init() {}

    func startFakefsRequestMonitor() {
        guard monitorTask == nil else { return }
        monitorTask = Task(priority: .utility) {
            await self.monitorLoop()
        }
    }

    func installBundledAssetsIfAvailable() async {
        guard !Self.installedAssetsAreUsable else { return }
        _ = try? Self.installFirstAvailableAssetDirectory()
    }

    func installFakefsCommandShims() async {
        await IshFS.repairCoreDevices()
        _ = await IshFS.run("mkdir -p /usr/local/bin \(Self.requestRoot) \(Self.buildRoot)")
        let script = Self.commandShimScript()
        for command in Self.commandNames {
            do {
                try await IshFS.writeTextFile(path: "/usr/local/bin/\(command)", text: script)
                _ = await IshFS.run("chmod +x /usr/local/bin/\(IshFS.shellQuote(command))")
            } catch {
                LLog.warn("buildkit", "failed to install fakefs command shim", fields: ["command": command, "error": error.localizedDescription])
            }
        }
        try? await IshFS.writeTextFile(path: Self.shimInstallMarker, text: Date().description)
    }

    func status() async -> LitterBuildKitStatus {
        let shimsInstalled = await IshFS.exists(path: Self.shimInstallMarker)
        let manifest = Self.installedManifest
        return LitterBuildKitStatus(
            sourceImportAvailable: Self.sourceImportAvailable,
            privateAssetsInstalled: manifest != nil,
            nativeCompilerAssetsInstalled: Self.nativeCompilerAssetsInstalled,
            nativeDriverInstalled: Self.nativeDriverInstalled,
            nativeDriverLoadable: Self.nativeDriverLoadable,
            supportLibrariesInstalled: Self.supportLibrariesInstalled,
            sdkInstalled: Self.sdkInstalled,
            commandShimsInstalled: shimsInstalled,
            requestMonitorRunning: monitorTask != nil,
            toolchainRoot: Self.toolchainRoot.path,
            sdkRoot: Self.sdkRoot.path,
            buildKitRoot: Self.buildKitRoot.path,
            commands: Self.commandNames,
            assetManifest: manifest
        )
    }

    private func monitorLoop() async {
        await installFakefsCommandShims()
        while !Task.isCancelled {
            await processPendingRequests()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func processPendingRequests() async {
        let list = await IshFS.run("find \(Self.requestRoot) -type f -name '*.request' 2>/dev/null | sort | head -n 8")
        guard list.exitCode == 0 else { return }
        let paths = list.output.split(separator: "\n").map(String.init)
        for path in paths {
            await processRequest(path: path)
        }
    }

    private func processRequest(path: String) async {
        guard let requestText = try? await IshFS.readTextFile(path: path, maxBytes: 32_000) else {
            _ = await IshFS.run("rm -f \(IshFS.shellQuote(path))")
            return
        }
        let request = Self.parseRequest(requestText)
        let id = request["id"] ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let command = request["command"] ?? "litter-buildkit"
        let cwd = request["cwd"] ?? "/root"
        let args = request["args"] ?? ""
        let buildDir = "\(Self.buildRoot)/\(id)"
        _ = await IshFS.run("mkdir -p \(IshFS.shellQuote(buildDir))")
        _ = await IshFS.run("rm -f \(IshFS.shellQuote(path))")

        let job = Task(priority: .userInitiated) {
            await self.handle(command: command, args: args, cwd: cwd, buildDir: buildDir)
        }
        activeJobs[id] = job
        let result = await job.value
        activeJobs.removeValue(forKey: id)
        try? await IshFS.writeTextFile(path: "\(buildDir)/status.txt", text: result.statusText)
        try? await IshFS.writeTextFile(path: "\(buildDir)/log.txt", text: result.logText)
    }

    private func handle(command: String, args: String, cwd: String, buildDir: String) async -> BuildKitCommandResult {
        switch command {
        case "litter-buildkit":
            let current = await status()
            return BuildKitCommandResult(exitCode: 0, status: "ready", log: Self.statusLog(current))
        case "litter-buildkit-install-assets":
            return installAssetsCommand()
        case "litter-fs-doctor":
            return await fakefsDoctor()
        case "litter-swift-check":
            return await swiftCheck(args: args, cwd: cwd, buildDir: buildDir)
        case "litter-swift-build", "litter-swift-test", "litter-ipa-build", "litter-ipa-package":
            return await nativeBuildCommand(command: command, args: args, cwd: cwd, buildDir: buildDir)
        case "litter-build-cancel":
            return cancelCommand(args: args)
        default:
            return BuildKitCommandResult(exitCode: 64, status: "unknown-command", log: "Unknown BuildKit command: \(command)\n")
        }
    }

    private func installAssetsCommand() -> BuildKitCommandResult {
        do {
            let manifest = try Self.installFirstAvailableAssetDirectory()
            return BuildKitCommandResult(
                exitCode: 0,
                status: "assets-installed",
                log: "Installed BuildKit assets: \(manifest.bundleIdentifier) SDK \(manifest.sdkVersion)\nRoot: \(Self.buildKitRoot.path)\n"
            )
        } catch {
            return BuildKitCommandResult(exitCode: 78, status: "assets-missing", log: "No installable private BuildKit asset directory was found.\n\(error.localizedDescription)\n")
        }
    }

    private func fakefsDoctor() async -> BuildKitCommandResult {
        let repair = await IshFS.repairCoreDevices()
        let checks = await IshFS.run(
            """
            set -eu
            ok=1
            check() { if eval "$2"; then echo "ok  $1"; else echo "bad $1"; ok=0; fi; }
            check "/dev/null char device" "[ -c /dev/null ]"
            check "/dev/random char device" "[ -c /dev/random ]"
            check "/dev/urandom char device" "[ -c /dev/urandom ]"
            check "/tmp writable" "t=$(mktemp /tmp/litter.XXXXXX) && rm -f \"$t\""
            check "/usr/local/bin writable" "[ -w /usr/local/bin ]"
            check "/root/builds writable" "[ -w /root/builds ]"
            if command -v git >/dev/null 2>&1; then
              tmp=$(mktemp -d /tmp/litter-git.XXXXXX)
              if git -C "$tmp" init >/dev/null 2>&1; then echo "ok  git temp files"; else echo "bad git temp files"; ok=0; fi
              rm -rf "$tmp"
            else
              echo "skip git temp files (git not installed)"
            fi
            exit $((ok == 1 ? 0 : 1))
            """
        )
        let status = checks.exitCode == 0 ? "doctor-ok" : "doctor-failed"
        return BuildKitCommandResult(exitCode: Int(checks.exitCode), status: status, log: "Repair output:\n\(repair.output)\nChecks:\n\(checks.output)")
    }

    private func swiftCheck(args: String, cwd: String, buildDir: String) async -> BuildKitCommandResult {
        let tokens = Self.shellWords(args)
        guard let first = tokens.first else {
            return BuildKitCommandResult(exitCode: 64, status: "missing-input", log: "Usage: litter-swift-check path/to/File.swift\n")
        }
        let path = first.hasPrefix("/") ? first : "\(cwd)/\(first)"
        let source = (try? await IshFS.readTextFile(path: path, maxBytes: 512_000)) ?? ""
        var log = "Litter BuildKit Swift check\n"
        log += "Input: \(path)\n"
        log += "Backend: Nyxian private asset pack + native driver\n\n"
        log += Self.staticSwiftPreflight(source: source, path: path)

        let status = await status()
        guard status.isReadyForNativeBuilds else {
            log += "\nBlocked: BuildKit is not ready for native Swift builds.\n"
            log += Self.missingAssetSummary(status)
            return BuildKitCommandResult(exitCode: 78, status: "toolchain-missing", log: log)
        }
        return await nativeBuildCommand(command: "litter-swift-check", args: args, cwd: cwd, buildDir: buildDir, prelude: log)
    }

    private func nativeBuildCommand(command: String, args: String, cwd: String, buildDir: String, prelude: String = "") async -> BuildKitCommandResult {
        let current = await status()
        guard current.isReadyForNativeBuilds else {
            var log = prelude
            log += "\(command) is routed through Litter BuildKit.\n"
            log += Self.missingAssetSummary(current)
            return BuildKitCommandResult(exitCode: 78, status: "toolchain-missing", log: log)
        }
        guard let result = Self.runNativeDriver(command: command, args: args, cwd: cwd, buildDir: buildDir) else {
            var log = prelude
            log += "Native BuildKit assets are present, but the private native driver did not expose litter_buildkit_run_json.\n"
            log += "Embed LitterBuildKitNative.framework in the private sideload IPA and link it to CoreCompiler.framework.\n"
            return BuildKitCommandResult(exitCode: 78, status: "adapter-missing", log: log)
        }
        if prelude.isEmpty { return result }
        return BuildKitCommandResult(exitCode: result.exitCode, status: result.status, log: prelude + "\n" + result.log)
    }

    private func cancelCommand(args: String) -> BuildKitCommandResult {
        let id = Self.shellWords(args).first
        if let id, let job = activeJobs[id] {
            job.cancel()
            activeJobs.removeValue(forKey: id)
            return BuildKitCommandResult(exitCode: 0, status: "cancelled", log: "Cancelled active BuildKit job \(id).\n")
        }
        return BuildKitCommandResult(exitCode: 0, status: "cancelled", log: "No matching active native BuildKit job was found.\n")
    }

    private static var documentsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    private static var buildKitRoot: URL {
        documentsRoot.appendingPathComponent("BuildKit", isDirectory: true)
    }

    private static var toolchainRoot: URL {
        buildKitRoot.appendingPathComponent("Toolchains/Nyxian", isDirectory: true)
    }

    private static var sdkRoot: URL {
        buildKitRoot.appendingPathComponent("SDK/iPhoneOS26.4.sdk", isDirectory: true)
    }

    private static var installedManifestURL: URL {
        buildKitRoot.appendingPathComponent("manifest.json")
    }

    private static var installedManifest: BuildKitAssetManifest? {
        guard let data = try? Data(contentsOf: installedManifestURL) else { return nil }
        return try? JSONDecoder().decode(BuildKitAssetManifest.self, from: data)
    }

    private static var installedAssetsAreUsable: Bool {
        installedManifest != nil && supportLibrariesInstalled && sdkInstalled
    }

    private static var nativeCompilerAssetsInstalled: Bool {
        fileExists(toolchainRoot.appendingPathComponent("CoreCompiler.framework")) || fileExists(embeddedFrameworkURL(named: "CoreCompiler"))
    }

    private static var nativeDriverInstalled: Bool {
        fileExists(nativeDriverURL) || fileExists(embeddedFrameworkURL(named: "LitterBuildKitNative"))
    }

    private static var nativeDriverLoadable: Bool {
        loadNativeDriverHandle() != nil
    }

    private static var supportLibrariesInstalled: Bool {
        fileExists(toolchainRoot.appendingPathComponent("CoreCompilerSupportLibs"))
    }

    private static var sdkInstalled: Bool {
        fileExists(sdkRoot.appendingPathComponent("SDKSettings.plist"))
    }

    private static var nativeDriverURL: URL {
        toolchainRoot.appendingPathComponent("LitterBuildKitNative.framework/LitterBuildKitNative")
    }

    private static var sourceImportAvailable: Bool {
        Bundle.main.url(forResource: "nyxian-import-manifest", withExtension: "json") != nil
    }

    private static func embeddedFrameworkURL(named name: String) -> URL {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("\(name).framework/\(name)") ?? Bundle.main.bundleURL.appendingPathComponent("Frameworks/\(name).framework/\(name)")
    }

    private static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func installFirstAvailableAssetDirectory() throws -> BuildKitAssetManifest {
        let candidates = [
            Bundle.main.url(forResource: "BuildKitAssets", withExtension: nil),
            documentsRoot.appendingPathComponent("BuildKitAssets", isDirectory: true),
            documentsRoot.appendingPathComponent("Inbox/BuildKitAssets", isDirectory: true)
        ].compactMap { $0 }

        for candidate in candidates where fileExists(candidate.appendingPathComponent("manifest.json")) {
            return try installAssetDirectory(candidate)
        }
        if fileExists(documentsRoot.appendingPathComponent("LitterBuildKitAssets.zip")) {
            throw NSError(domain: "LitterBuildKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Found LitterBuildKitAssets.zip, but ZIP extraction must happen in the private build workflow before app launch. Import an expanded BuildKitAssets directory or rebuild the IPA with bundled assets."])
        }
        throw NSError(domain: "LitterBuildKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected BuildKitAssets/manifest.json in the app bundle, Documents, or Documents/Inbox."])
    }

    private static func installAssetDirectory(_ source: URL) throws -> BuildKitAssetManifest {
        let manifest = try validateAssetDirectory(source)
        let fm = FileManager.default
        let stage = documentsRoot.appendingPathComponent("BuildKit.installing", isDirectory: true)
        let previous = documentsRoot.appendingPathComponent("BuildKit.previous", isDirectory: true)
        try? fm.removeItem(at: stage)
        try? fm.removeItem(at: previous)
        try fm.createDirectory(at: stage.deletingLastPathComponent(), withIntermediateDirectories: true)
        try copyDirectoryContents(from: source, to: stage)
        _ = try validateAssetDirectory(stage)
        if fm.fileExists(atPath: buildKitRoot.path) {
            try fm.moveItem(at: buildKitRoot, to: previous)
        }
        do {
            try fm.moveItem(at: stage, to: buildKitRoot)
            try? fm.removeItem(at: previous)
        } catch {
            if fm.fileExists(atPath: previous.path) {
                try? fm.moveItem(at: previous, to: buildKitRoot)
            }
            throw error
        }
        return manifest
    }

    private static func copyDirectoryContents(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            try fm.copyItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent, isDirectory: item.hasDirectoryPath))
        }
    }

    private static func validateAssetDirectory(_ root: URL) throws -> BuildKitAssetManifest {
        let manifestURL = root.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(BuildKitAssetManifest.self, from: data)
        var required = manifest.requiredPaths
        required.append(manifest.toolchain.coreCompilerFramework)
        required.append(manifest.toolchain.supportLibraries)
        required.append(manifest.toolchain.sdkPath)
        if let driver = manifest.toolchain.nativeDriverFramework { required.append(driver) }
        for relative in Set(required) {
            let path = root.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: path.path) else {
                throw NSError(domain: "LitterBuildKit", code: 3, userInfo: [NSLocalizedDescriptionKey: "BuildKit asset bundle is missing required path: \(relative)"])
            }
        }
        if let hashes = manifest.sha256 {
            for (relative, expected) in hashes {
                let path = root.appendingPathComponent(relative)
                guard FileManager.default.fileExists(atPath: path.path) else {
                    throw NSError(domain: "LitterBuildKit", code: 4, userInfo: [NSLocalizedDescriptionKey: "BuildKit hash listed missing file: \(relative)"])
                }
                let actual = try sha256Hex(path)
                guard actual.lowercased() == expected.lowercased() else {
                    throw NSError(domain: "LitterBuildKit", code: 5, userInfo: [NSLocalizedDescriptionKey: "BuildKit hash mismatch for \(relative)"])
                }
            }
        }
        return manifest
    }

    private static func sha256Hex(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func loadNativeDriverHandle() -> UnsafeMutableRawPointer? {
        let candidates = [embeddedFrameworkURL(named: "LitterBuildKitNative"), nativeDriverURL]
        for candidate in candidates where fileExists(candidate) {
            if let handle = dlopen(candidate.path, RTLD_NOW | RTLD_LOCAL), dlsym(handle, "litter_buildkit_run_json") != nil {
                return handle
            }
        }
        return nil
    }

    private static func runNativeDriver(command: String, args: String, cwd: String, buildDir: String) -> BuildKitCommandResult? {
        guard let handle = loadNativeDriverHandle(), let symbol = dlsym(handle, "litter_buildkit_run_json") else { return nil }
        typealias RunFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
        let run = unsafeBitCast(symbol, to: RunFn.self)
        let payload = NativeDriverRequest(
            command: command,
            args: args,
            cwd: cwd,
            buildDir: buildDir,
            buildKitRoot: buildKitRoot.path,
            toolchainRoot: toolchainRoot.path,
            sdkRoot: sdkRoot.path
        )
        guard let data = try? JSONEncoder().encode(payload), let json = String(data: data, encoding: .utf8) else {
            return BuildKitCommandResult(exitCode: 70, status: "request-encode-failed", log: "Could not encode native BuildKit request.\n")
        }
        guard let responsePointer = json.withCString({ run($0) }) else {
            return BuildKitCommandResult(exitCode: 70, status: "driver-failed", log: "Native BuildKit driver returned no response.\n")
        }
        let responseJSON = String(cString: responsePointer)
        if let freeSymbol = dlsym(handle, "litter_buildkit_free_string") {
            typealias FreeFn = @convention(c) (UnsafeMutablePointer<CChar>) -> Void
            unsafeBitCast(freeSymbol, to: FreeFn.self)(responsePointer)
        }
        guard let responseData = responseJSON.data(using: .utf8), let response = try? JSONDecoder().decode(NativeDriverResponse.self, from: responseData) else {
            return BuildKitCommandResult(exitCode: 70, status: "driver-response-invalid", log: responseJSON)
        }
        return BuildKitCommandResult(exitCode: response.exitCode, status: response.status, log: response.log)
    }

    private static func parseRequest(_ text: String) -> [String: String] {
        var output: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq])
            let value = String(line[line.index(after: eq)...])
            output[key] = value
        }
        return output
    }

    private static func shellWords(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
    }

    private static func staticSwiftPreflight(source: String, path: String) -> String {
        guard !source.isEmpty else { return "Static preflight: source is empty or could not be read.\n" }
        var output = "Static preflight:\n"
        let pairs: [(Character, Character, String)] = [("{", "}", "braces"), ("(", ")", "parentheses"), ("[", "]", "brackets")]
        for pair in pairs {
            let opens = source.filter { $0 == pair.0 }.count
            let closes = source.filter { $0 == pair.1 }.count
            if opens == closes {
                output += "- Balanced \(pair.2): \(opens)/\(closes).\n"
            } else {
                output += "- Unbalanced \(pair.2): \(opens)/\(closes).\n"
            }
        }
        if source.contains("import SwiftUI") || source.contains("import UIKit") {
            output += "- iOS UI framework import detected. Full validation needs the iPhoneOS SDK.\n"
        }
        if source.contains("#Preview") {
            output += "- SwiftUI preview macro detected. On-device preview rendering is not part of BuildKit v1.\n"
        }
        if source.count > 200_000 {
            output += "- Large source file; native compiler diagnostics will be required for reliable checking.\n"
        }
        output += "- File: \(path)\n"
        return output
    }

    private static func statusLog(_ status: LitterBuildKitStatus) -> String {
        var output = """
        Litter BuildKit status
        Source import: \(status.sourceImportAvailable ? "present" : "missing")
        Private assets: \(status.privateAssetsInstalled ? "installed" : "missing")
        CoreCompiler assets: \(status.nativeCompilerAssetsInstalled ? "installed" : "missing")
        Native driver: \(status.nativeDriverInstalled ? "installed" : "missing")
        Native driver loadable: \(status.nativeDriverLoadable ? "yes" : "no")
        Swift support libraries: \(status.supportLibrariesInstalled ? "installed" : "missing")
        iPhoneOS SDK: \(status.sdkInstalled ? "installed" : "missing")
        Fakefs command shims: \(status.commandShimsInstalled ? "installed" : "missing")
        Request monitor: \(status.requestMonitorRunning ? "running" : "stopped")
        BuildKit root: \(status.buildKitRoot)
        Toolchain root: \(status.toolchainRoot)
        SDK root: \(status.sdkRoot)
        Commands: \(status.commands.joined(separator: ", "))
        """
        if let manifest = status.assetManifest {
            output += "\nManifest: \(manifest.bundleIdentifier) SDK \(manifest.sdkVersion) Swift \(manifest.swiftVersion ?? "unknown")\n"
            output += "Capabilities: \(manifest.capabilities.joined(separator: ", "))\n"
        }
        return output
    }

    private static func missingAssetSummary(_ status: LitterBuildKitStatus) -> String {
        var lines: [String] = []
        if !status.privateAssetsInstalled { lines.append("- Missing private BuildKit asset manifest at \(status.buildKitRoot)/manifest.json.") }
        if !status.nativeCompilerAssetsInstalled { lines.append("- Missing CoreCompiler.framework in private assets or embedded app frameworks.") }
        if !status.nativeDriverInstalled { lines.append("- Missing LitterBuildKitNative.framework private driver.") }
        if status.nativeDriverInstalled && !status.nativeDriverLoadable { lines.append("- Native driver exists but cannot be loaded or lacks litter_buildkit_run_json.") }
        if !status.supportLibrariesInstalled { lines.append("- Missing CoreCompilerSupportLibs.") }
        if !status.sdkInstalled { lines.append("- Missing iPhoneOS26.4.sdk/SDKSettings.plist.") }
        if lines.isEmpty { return "- BuildKit assets look present, but native execution failed.\n" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func commandShimScript() -> String {
        """
        #!/bin/sh
        set -eu
        root=/root/.litter-buildkit
        requests="$root/requests"
        builds=/root/builds
        mkdir -p "$requests" "$builds"
        cmd="${0##*/}"
        if [ "$cmd" = "litter-build-status" ]; then
          if [ "${1:-}" = "" ]; then
            find "$builds" -maxdepth 2 -name status.txt -print 2>/dev/null | sort | tail -n 20
            exit 0
          fi
          id="$1"
          if [ -f "$builds/$id/status.txt" ]; then cat "$builds/$id/status.txt"; fi
          if [ -f "$builds/$id/log.txt" ]; then printf '\n'; cat "$builds/$id/log.txt"; fi
          exit 0
        fi
        wait_for_result=1
        timeout="${LITTER_BUILDKIT_TIMEOUT:-120}"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --no-wait)
              wait_for_result=0
              shift
              ;;
            --timeout)
              if [ "${2:-}" = "" ]; then
                echo "Missing timeout value" >&2
                exit 64
              fi
              timeout="$2"
              shift 2
              ;;
            *)
              break
              ;;
          esac
        done
        id="$(date +%Y%m%d%H%M%S)-$$"
        req="$requests/$id.request"
        {
          printf 'id=%s\n' "$id"
          printf 'command=%s\n' "$cmd"
          printf 'cwd=%s\n' "$(pwd)"
          printf 'args=%s\n' "$*"
        } > "$req"
        if [ "$wait_for_result" -eq 0 ]; then
          echo "Queued Litter BuildKit request: $id"
          echo "Status: litter-build-status $id"
          echo "Log: /root/builds/$id/log.txt"
          exit 0
        fi

        elapsed=0
        while [ "$elapsed" -lt "$timeout" ]; do
          if [ -f "$builds/$id/status.txt" ]; then
            cat "$builds/$id/status.txt"
            if [ -f "$builds/$id/log.txt" ]; then
              printf '\n'
              cat "$builds/$id/log.txt"
            fi
            code="$(awk -F= '/^exitCode=/{print $2; exit}' "$builds/$id/status.txt" 2>/dev/null || true)"
            case "$code" in
              ''|*[!0-9]*)
                exit 1
                ;;
              *)
                exit "$code"
                ;;
            esac
          fi
          sleep 1
          elapsed=$((elapsed + 1))
        done
        echo "Timed out waiting for Litter BuildKit request: $id" >&2
        echo "Status: litter-build-status $id" >&2
        exit 124
        """
    }
}

private struct NativeDriverRequest: Encodable, Sendable {
    var command: String
    var args: String
    var cwd: String
    var buildDir: String
    var buildKitRoot: String
    var toolchainRoot: String
    var sdkRoot: String
}

private struct NativeDriverResponse: Decodable, Sendable {
    var exitCode: Int
    var status: String
    var log: String
}

private struct BuildKitCommandResult: Sendable {
    var exitCode: Int
    var status: String
    var log: String

    var statusText: String {
        "exitCode=\(exitCode)\nstatus=\(status)\nupdatedAt=\(ISO8601DateFormatter().string(from: Date()))\n"
    }

    var logText: String { log }
}
