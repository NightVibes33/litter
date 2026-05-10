import Foundation

struct LitterBuildKitStatus: Equatable {
    var sourceImportAvailable: Bool
    var nativeCompilerAssetsInstalled: Bool
    var sdkInstalled: Bool
    var commandShimsInstalled: Bool
    var requestMonitorRunning: Bool
    var toolchainRoot: String
    var sdkRoot: String
    var commands: [String]

    var readinessTitle: String {
        if nativeCompilerAssetsInstalled && sdkInstalled { return "On-device compiler ready" }
        if sourceImportAvailable { return "Nyxian source imported" }
        return "BuildKit source missing"
    }

    var readinessDetail: String {
        if nativeCompilerAssetsInstalled && sdkInstalled {
            return "Litter can route fakefs build requests to native compiler assets."
        }
        if sourceImportAvailable {
            return "The Nyxian source import is present, but CoreCompiler/Swift toolchain assets still need to be packaged before Swift compilation can run on-device."
        }
        return "ThirdParty/Nyxian is missing from this build."
    }
}

actor LitterBuildKit {
    static let shared = LitterBuildKit()

    private static let requestRoot = "/root/.litter-buildkit/requests"
    private static let buildRoot = "/root/builds"
    private static let shimInstallMarker = "/root/.litter-buildkit/shims-installed-v1"
    private static let commandNames = [
        "litter-buildkit",
        "litter-swift-check",
        "litter-swift-test",
        "litter-ipa-build",
        "litter-ipa-package",
        "litter-build-status",
        "litter-build-cancel"
    ]

    private var monitorTask: Task<Void, Never>?

    private init() {}

    func startFakefsRequestMonitor() {
        guard monitorTask == nil else { return }
        monitorTask = Task(priority: .utility) {
            await self.monitorLoop()
        }
    }

    func installFakefsCommandShims() async {
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
        return LitterBuildKitStatus(
            sourceImportAvailable: Self.sourceImportAvailable,
            nativeCompilerAssetsInstalled: Self.nativeCompilerAssetsInstalled,
            sdkInstalled: Self.sdkInstalled,
            commandShimsInstalled: shimsInstalled,
            requestMonitorRunning: monitorTask != nil,
            toolchainRoot: Self.toolchainRoot.path,
            sdkRoot: Self.sdkRoot.path,
            commands: Self.commandNames
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

        let result = await handle(command: command, args: args, cwd: cwd, buildDir: buildDir)
        try? await IshFS.writeTextFile(path: "\(buildDir)/status.txt", text: result.statusText)
        try? await IshFS.writeTextFile(path: "\(buildDir)/log.txt", text: result.logText)
    }

    private func handle(command: String, args: String, cwd: String, buildDir: String) async -> BuildKitCommandResult {
        switch command {
        case "litter-buildkit":
            let current = await status()
            return BuildKitCommandResult(exitCode: 0, status: "ready", log: Self.statusLog(current))
        case "litter-swift-check":
            return await swiftCheck(args: args, cwd: cwd)
        case "litter-swift-test", "litter-ipa-build", "litter-ipa-package":
            return unavailableCompilerResult(command: command)
        case "litter-build-cancel":
            return BuildKitCommandResult(exitCode: 0, status: "cancelled", log: "No active native BuildKit job cancellation hook is registered yet.\n")
        default:
            return BuildKitCommandResult(exitCode: 64, status: "unknown-command", log: "Unknown BuildKit command: \(command)\n")
        }
    }

    private func swiftCheck(args: String, cwd: String) async -> BuildKitCommandResult {
        let tokens = Self.shellWords(args)
        guard let first = tokens.first else {
            return BuildKitCommandResult(exitCode: 64, status: "missing-input", log: "Usage: litter-swift-check path/to/File.swift\n")
        }
        let path = first.hasPrefix("/") ? first : "\(cwd)/\(first)"
        let source = (try? await IshFS.readTextFile(path: path, maxBytes: 512_000)) ?? ""
        var log = "Litter BuildKit Swift check\n"
        log += "Input: \(path)\n"
        log += "Backend: Nyxian source import + Litter native bridge\n\n"
        log += Self.staticSwiftPreflight(source: source, path: path)
        if Self.nativeCompilerAssetsInstalled && Self.sdkInstalled {
            log += "\nNative compiler assets are present, but the CoreCompiler invocation adapter is not enabled in this build yet.\n"
            return BuildKitCommandResult(exitCode: 78, status: "adapter-pending", log: log)
        }
        log += "\nBlocked: CoreCompiler.framework, Swift support libraries, and iPhoneOS SDK assets are not installed in Litter BuildKit storage yet.\n"
        log += "Next required step: package the imported Nyxian LLVM-On-iOS/CoreCompiler assets into the app or downloadable BuildKit bundle.\n"
        return BuildKitCommandResult(exitCode: 78, status: "toolchain-missing", log: log)
    }

    private func unavailableCompilerResult(command: String) -> BuildKitCommandResult {
        var log = "\(command) is routed through Litter BuildKit.\n"
        log += "Nyxian source has been imported, but native compiler/toolchain assets are not installed yet.\n"
        log += "Until those assets are packaged, use the GitHub unsigned IPA workflow for full iOS builds.\n"
        return BuildKitCommandResult(exitCode: 78, status: "toolchain-missing", log: log)
    }

    private static var documentsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    private static var toolchainRoot: URL {
        documentsRoot.appendingPathComponent("BuildKit/Toolchains/Nyxian", isDirectory: true)
    }

    private static var sdkRoot: URL {
        documentsRoot.appendingPathComponent("BuildKit/SDK/iPhoneOS26.4.sdk", isDirectory: true)
    }

    private static var nativeCompilerAssetsInstalled: Bool {
        FileManager.default.fileExists(atPath: toolchainRoot.appendingPathComponent("CoreCompiler.framework").path)
    }

    private static var sdkInstalled: Bool {
        FileManager.default.fileExists(atPath: sdkRoot.appendingPathComponent("SDKSettings.plist").path)
    }

    private static var sourceImportAvailable: Bool {
        Bundle.main.url(forResource: "nyxian-import-manifest", withExtension: "json") != nil
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
        """
        Litter BuildKit status
        Source import: \(status.sourceImportAvailable ? "present" : "missing")
        Native compiler assets: \(status.nativeCompilerAssetsInstalled ? "installed" : "missing")
        iPhoneOS SDK: \(status.sdkInstalled ? "installed" : "missing")
        Fakefs command shims: \(status.commandShimsInstalled ? "installed" : "missing")
        Request monitor: \(status.requestMonitorRunning ? "running" : "stopped")
        Toolchain root: \(status.toolchainRoot)
        SDK root: \(status.sdkRoot)
        Commands: \(status.commands.joined(separator: ", "))
        """
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

private struct BuildKitCommandResult {
    var exitCode: Int
    var status: String
    var log: String

    var statusText: String {
        "exitCode=\(exitCode)\nstatus=\(status)\nupdatedAt=\(ISO8601DateFormatter().string(from: Date()))\n"
    }

    var logText: String { log }
}
