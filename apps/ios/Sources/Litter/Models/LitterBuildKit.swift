import CryptoKit
import Darwin
import Foundation
import ZIPFoundation

struct BuildKitAssetManifest: Codable, Equatable, Sendable {
    struct Toolchain: Codable, Equatable, Sendable {
        var name: String
        var coreCompilerFramework: String
        var nativeDriverFramework: String?
        var nativeRunner: String?
        var nativeDriverMode: String?
        var supportLibraries: String
        var sdkPath: String
        var clangResourceDir: String?
        var swiftResourceDir: String?
        var cxxStandardLibraryIncludeDir: String?

        enum CodingKeys: String, CodingKey {
            case name
            case coreCompilerFramework
            case nativeDriverFramework
            case nativeRunner
            case nativeDriverMode
            case supportLibraries
            case sdkPath
            case clangResourceDir
            case swiftResourceDir
            case cxxStandardLibraryIncludeDir
        }

        init(
            name: String,
            coreCompilerFramework: String,
            nativeDriverFramework: String?,
            nativeRunner: String?,
            nativeDriverMode: String? = "runner",
            supportLibraries: String,
            sdkPath: String,
            clangResourceDir: String? = nil,
            swiftResourceDir: String? = nil,
            cxxStandardLibraryIncludeDir: String? = nil
        ) {
            self.name = name
            self.coreCompilerFramework = coreCompilerFramework
            self.nativeDriverFramework = nativeDriverFramework
            self.nativeRunner = nativeRunner
            self.nativeDriverMode = nativeDriverMode
            self.supportLibraries = supportLibraries
            self.sdkPath = sdkPath
            self.clangResourceDir = clangResourceDir
            self.swiftResourceDir = swiftResourceDir
            self.cxxStandardLibraryIncludeDir = cxxStandardLibraryIncludeDir
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            coreCompilerFramework = try container.decode(String.self, forKey: .coreCompilerFramework)
            nativeDriverFramework = try container.decodeIfPresent(String.self, forKey: .nativeDriverFramework)
            nativeRunner = try container.decodeIfPresent(String.self, forKey: .nativeRunner)
            nativeDriverMode = try container.decodeIfPresent(String.self, forKey: .nativeDriverMode) ?? "runner"
            supportLibraries = try container.decode(String.self, forKey: .supportLibraries)
            sdkPath = try container.decode(String.self, forKey: .sdkPath)
            clangResourceDir = try container.decodeIfPresent(String.self, forKey: .clangResourceDir)
            swiftResourceDir = try container.decodeIfPresent(String.self, forKey: .swiftResourceDir)
            cxxStandardLibraryIncludeDir = try container.decodeIfPresent(String.self, forKey: .cxxStandardLibraryIncludeDir)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(coreCompilerFramework, forKey: .coreCompilerFramework)
            try container.encodeIfPresent(nativeDriverFramework, forKey: .nativeDriverFramework)
            try container.encodeIfPresent(nativeRunner, forKey: .nativeRunner)
            try container.encodeIfPresent(nativeDriverMode, forKey: .nativeDriverMode)
            try container.encode(supportLibraries, forKey: .supportLibraries)
            try container.encode(sdkPath, forKey: .sdkPath)
            try container.encodeIfPresent(clangResourceDir, forKey: .clangResourceDir)
            try container.encodeIfPresent(swiftResourceDir, forKey: .swiftResourceDir)
            try container.encodeIfPresent(cxxStandardLibraryIncludeDir, forKey: .cxxStandardLibraryIncludeDir)
        }
    }

    var schemaVersion: Int
    var bundleIdentifier: String
    var createdAt: String?
    var sdkVersion: String
    var swiftVersion: String?
    var swiftCompatibilityVersion: String?
    var sdkSwiftVersion: String?
    var minimumIOS: String?
    var toolchain: Toolchain
    var capabilities: [String]
    var requiredPaths: [String]
    var sha256: [String: String]?
}

struct BuildKitSourceImportManifest: Codable, Equatable, Sendable {
    struct LiveContainer: Codable, Equatable, Sendable {
        var sourceIncluded: Bool
        var zsignIncluded: Bool
        var openSSLFrameworkIncluded: Bool
        var notes: [String]
    }

    var name: String
    var license: String
    var sourceRepositories: [String]
    var importedFileCount: Int
    var purpose: String
    var includedCapabilities: [String]?
    var requiredPrivateAssets: [String]?
    var knownSourceGaps: [String]?
    var liveContainer: LiveContainer?
}

struct LitterBuildProjectManifest: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var name: String
    var bundleIdentifier: String
    var deploymentTarget: String
    var sdk: String?
    var product: String
    var entrypoint: String?
    var sources: [String]
    var resources: [String]?
    var entitlements: String?
    var output: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case name
        case bundleIdentifier
        case deploymentTarget
        case sdk
        case product
        case entrypoint
        case sources
        case resources
        case entitlements
        case output
    }

    init(
        schemaVersion: Int,
        name: String,
        bundleIdentifier: String,
        deploymentTarget: String,
        sdk: String?,
        product: String,
        entrypoint: String?,
        sources: [String],
        resources: [String]?,
        entitlements: String?,
        output: String?
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.deploymentTarget = deploymentTarget
        self.sdk = sdk
        self.product = product
        self.entrypoint = entrypoint
        self.sources = sources
        self.resources = resources
        self.entitlements = entitlements
        self.output = output
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        name = try container.decode(String.self, forKey: .name)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        deploymentTarget = try container.decode(String.self, forKey: .deploymentTarget)
        sdk = try container.decodeIfPresent(String.self, forKey: .sdk)
        product = try container.decode(String.self, forKey: .product)
        entrypoint = try container.decodeIfPresent(String.self, forKey: .entrypoint)
        sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? []
        resources = try container.decodeIfPresent([String].self, forKey: .resources)
        entitlements = try container.decodeIfPresent(String.self, forKey: .entitlements)
        output = try container.decodeIfPresent(String.self, forKey: .output)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(name, forKey: .name)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(deploymentTarget, forKey: .deploymentTarget)
        try container.encodeIfPresent(sdk, forKey: .sdk)
        try container.encode(product, forKey: .product)
        try container.encodeIfPresent(entrypoint, forKey: .entrypoint)
        try container.encode(sources, forKey: .sources)
        try container.encodeIfPresent(resources, forKey: .resources)
        try container.encodeIfPresent(entitlements, forKey: .entitlements)
        try container.encodeIfPresent(output, forKey: .output)
    }
}

private struct BuildKitHostStaging: Sendable {
    var log: String
    var hostWorkDir: String?
    var hostProjectPath: String?
    var hostInputPath: String?
    var fakefsProjectPath: String?
}

struct LitterBuildKitStatus: Equatable, Sendable {
    var sourceImportAvailable: Bool
    var liveContainerSourceAvailable: Bool
    var openSSLFrameworkVendored: Bool
    var privateAssetsInstalled: Bool
    var nativeCompilerAssetsInstalled: Bool
    var nativeDriverInstalled: Bool
    var nativeDriverLoadable: Bool
    var nativeDriverDiagnostics: [String]
    var nativeRunnerInstalled: Bool
    var supportLibrariesInstalled: Bool
    var sdkInstalled: Bool
    var clangResourceDirInstalled: Bool
    var swiftResourceDirInstalled: Bool
    var cxxStandardLibraryHeadersInstalled: Bool
    var commandShimsInstalled: Bool
    var requestMonitorRunning: Bool
    var toolchainRoot: String
    var sdkRoot: String
    var buildKitRoot: String
    var commands: [String]
    var assetManifest: BuildKitAssetManifest?
    var sourceImportManifest: BuildKitSourceImportManifest?

    var installedCapabilities: [String] {
        assetManifest?.capabilities.sorted() ?? []
    }

    var canRunSwiftDirectly: Bool {
        isReadyForNativeBuilds && installedCapabilities.contains("swift-check") && installedCapabilities.contains("swift-build")
    }

    var canBuildUnsignedIPA: Bool {
        isReadyForNativeBuilds && (installedCapabilities.contains("unsigned-ipa-build") || installedCapabilities.contains("unsigned-ipa-package"))
    }

    var missingRequirements: [String] {
        var lines: [String] = []
        if !privateAssetsInstalled { lines.append("private BuildKit asset manifest") }
        if !nativeCompilerAssetsInstalled { lines.append("CoreCompiler.framework") }
        if !nativeDriverInstalled { lines.append("LitterBuildKitNative.framework") }
        if nativeDriverInstalled && !nativeDriverLoadable { lines.append("loadable native driver with litter_buildkit_run_json") }
        if !nativeRunnerInstalled { lines.append("Nyxian BuildKit runner declared by the asset manifest") }
        if !supportLibrariesInstalled { lines.append("CoreCompilerSupportLibs") }
        if !sdkInstalled { lines.append("iPhoneOS SDKSettings.plist") }
        if !clangResourceDirInstalled { lines.append("Clang resource directory with builtin headers") }
        if !swiftResourceDirInstalled { lines.append("Swift resource directory") }
        if !cxxStandardLibraryHeadersInstalled { lines.append("libc++ standard library headers") }
        return lines
    }

    var isReadyForNativeBuilds: Bool {
        nativeCompilerAssetsInstalled && nativeDriverLoadable && nativeRunnerInstalled && supportLibrariesInstalled && sdkInstalled && clangResourceDirInstalled && swiftResourceDirInstalled && cxxStandardLibraryHeadersInstalled
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
            var detail = "The focused Nyxian source import is present. Install a private LitterBuildKitAssets bundle containing CoreCompiler, Swift support libraries, and iPhoneOS SDK assets to enable real local builds."
            if liveContainerSourceAvailable {
                detail += " LiveContainer/ZSign source is included for signing/install research paths."
            }
            if !openSSLFrameworkVendored {
                detail += " OpenSSL.xcframework is not bundled, so upstream LiveContainer/ZSign framework builds are blocked until it is restored."
            }
            return detail
        }
        return "ThirdParty/Nyxian is missing from this build."
    }
}

actor LitterBuildKit {
    static let shared = LitterBuildKit()

    private static let stateRoot = "/root/.litter/buildkit"
    private static let requestRoot = "\(stateRoot)/requests"
    private static let buildRoot = "/root/.litter/builds"
    private static let shimInstallMarker = "\(stateRoot)/shims-installed-v6"
    private static let canonicalCommandNames = [
        "litter-buildkit",
        "litter-nyxian-status",
        "litter-buildkit-install-assets",
        "litter-fs-doctor",
        "litter-env-report",
        "litter-dev-bootstrap",
        "litter-swift-check",
        "litter-swift-selftest",
        "litter-swiftc",
        "litter-swift-build",
        "litter-swift-test",
        "litter-ipa-build",
        "litter-ipa-package",
        "litter-clang",
        "litter-ld",
        "litter-build-status",
        "litter-build-cancel"
    ]
    private static let nativeCompatibilityCommandNames = [
        "swift",
        "swiftc",
        "clang",
        "clang++",
        "cc",
        "c++",
        "ld",
        "ld64",
        "xcodebuild",
        "xcode-select",
        "xcrun",
        "plutil",
        "code"
    ]
    private static let passThroughCommandNames = [
        "ar",
        "llvm-ar",
        "ranlib",
        "llvm-ranlib",
        "nm",
        "llvm-nm",
        "objdump",
        "llvm-objdump",
        "strip",
        "strings",
        "lipo"
    ]
    private static let commandNames = canonicalCommandNames + nativeCompatibilityCommandNames + passThroughCommandNames
    private static let cFamilySourceExtensions: Set<String> = ["c", "cc", "cpp", "cxx", "m", "mm"]
    private static let linkInputExtensions: Set<String> = ["o", "a", "dylib", "tbd"]

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
        guard !Self.installedAssetsAreUsable else {
            LLog.info("buildkit", "private BuildKit assets already installed")
            return
        }

        let source = Self.firstAvailableAssetCandidateDescription()
        do {
            let manifest = try Self.installFirstAvailableAssetDirectory()
            LLog.info(
                "buildkit",
                "installed private BuildKit assets",
                fields: [
                    "bundle": manifest.bundleIdentifier,
                    "sdk": manifest.sdkVersion,
                    "source": source,
                    "root": Self.buildKitRoot.path
                ]
            )
        } catch {
            LLog.warn(
                "buildkit",
                "private BuildKit assets were not installed",
                fields: [
                    "error": error.localizedDescription,
                    "search": Self.assetAvailabilityReport()
                ]
            )
        }
    }

    func importAssetBundle(from url: URL) async -> String {
        if url.pathExtension.lowercased() == "zip" {
            return await importAssetZip(from: url)
        }

        let shouldStop = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStop { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let source = try Self.resolveAssetDirectory(url)
            let manifest = try Self.installAssetDirectory(source)
            return "Installed BuildKit assets: \(manifest.bundleIdentifier) SDK \(manifest.sdkVersion)\nRoot: \(Self.buildKitRoot.path)\n"
        } catch {
            return "BuildKit asset import failed.\n\(error.localizedDescription)\n"
        }
    }

    func importAssetZip(from url: URL) async -> String {
        let shouldStop = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStop { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let manifest = try Self.installAssetZip(url)
            return "Installed BuildKit assets: \(manifest.bundleIdentifier) SDK \(manifest.sdkVersion)\nRoot: \(Self.buildKitRoot.path)\n"
        } catch {
            return "BuildKit asset ZIP import failed.\n\(error.localizedDescription)\n"
        }
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
        let sourceManifest = Self.sourceImportManifest
        let nativeDriverLoad = Self.loadNativeDriver()
        return LitterBuildKitStatus(
            sourceImportAvailable: Self.sourceImportAvailable,
            liveContainerSourceAvailable: sourceManifest?.liveContainer?.sourceIncluded ?? false,
            openSSLFrameworkVendored: sourceManifest?.liveContainer?.openSSLFrameworkIncluded ?? false,
            privateAssetsInstalled: manifest != nil,
            nativeCompilerAssetsInstalled: Self.nativeCompilerAssetsInstalled,
            nativeDriverInstalled: Self.nativeDriverInstalled,
            nativeDriverLoadable: nativeDriverLoad.handle != nil,
            nativeDriverDiagnostics: nativeDriverLoad.diagnostics,
            nativeRunnerInstalled: Self.nativeRunnerInstalled,
            supportLibrariesInstalled: Self.supportLibrariesInstalled,
            sdkInstalled: Self.sdkInstalled,
            clangResourceDirInstalled: Self.clangResourceDirInstalled,
            swiftResourceDirInstalled: Self.swiftResourceDirInstalled,
            cxxStandardLibraryHeadersInstalled: Self.cxxStandardLibraryHeadersInstalled,
            commandShimsInstalled: shimsInstalled,
            requestMonitorRunning: monitorTask != nil,
            toolchainRoot: Self.toolchainRoot.path,
            sdkRoot: Self.sdkRoot.path,
            buildKitRoot: Self.buildKitRoot.path,
            commands: Self.commandNames,
            assetManifest: manifest,
            sourceImportManifest: sourceManifest
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
        case "litter-nyxian-status":
            let current = await status()
            return BuildKitCommandResult(exitCode: 0, status: current.isReadyForNativeBuilds ? "nyxian-ready" : "nyxian-blocked", log: Self.nyxianStatusLog(current))
        case "litter-buildkit-install-assets":
            return installAssetsCommand()
        case "litter-fs-doctor":
            return await fakefsDoctor()
        case "litter-env-report":
            return await envReport()
        case "litter-dev-bootstrap":
            return await devBootstrap()
        case "litter-swift-check":
            return await swiftCheck(args: args, cwd: cwd, buildDir: buildDir)
        case "litter-swift-selftest":
            return await swiftSelfTest(cwd: cwd, buildDir: buildDir)
        case "litter-swiftc":
            return await swiftcCompile(args: args, cwd: cwd, buildDir: buildDir, compatibilityName: "litter-swiftc")
        case "litter-swift-build", "litter-swift-test", "litter-ipa-build", "litter-ipa-package":
            return await nativeBuildCommand(command: command, args: args, cwd: cwd, buildDir: buildDir)
        case "litter-clang":
            return await clangCompatibility(command: "clang", args: args, cwd: cwd, buildDir: buildDir)
        case "litter-ld":
            return await ldCompatibility(command: "ld", args: args, cwd: cwd, buildDir: buildDir)
        case "swift":
            return await swiftCompatibility(args: args, cwd: cwd, buildDir: buildDir)
        case "swiftc":
            return await swiftcCompile(args: args, cwd: cwd, buildDir: buildDir, compatibilityName: "swiftc")
        case "clang", "clang++", "cc", "c++":
            return await clangCompatibility(command: command, args: args, cwd: cwd, buildDir: buildDir)
        case "ld", "ld64":
            return await ldCompatibility(command: command, args: args, cwd: cwd, buildDir: buildDir)
        case "xcodebuild":
            return await xcodebuildCompatibility(args: args, cwd: cwd, buildDir: buildDir)
        case "xcode-select":
            return await xcodeSelectCompatibility(args: args)
        case "xcrun":
            return await xcrunCompatibility(args: args, cwd: cwd, buildDir: buildDir)
        case "plutil":
            return await plutilCompatibility(args: args, cwd: cwd)
        case "code":
            return codeCompatibility(args: args, cwd: cwd)
        case "ar", "llvm-ar", "ranlib", "llvm-ranlib", "nm", "llvm-nm", "objdump", "llvm-objdump", "strip", "strings", "lipo":
            return await passThroughTool(command: command, args: args)
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
            return BuildKitCommandResult(exitCode: 78, status: "assets-missing", log: "No installable private BuildKit asset directory was found.\n\(error.localizedDescription)\n\nAsset search:\n\(Self.assetAvailabilityReport())\n")
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
            check "/tmp writable" 't=$(mktemp /tmp/litter.XXXXXX) && rm -f "$t"'
            check "/usr/local/bin writable" "[ -w /usr/local/bin ]"
            check "/root/.litter/builds writable" "[ -w /root/.litter/builds ]"
            check "/root/litter visible" "[ -d /root/litter ] && cd /root/litter"
            for tool in \(Self.commandNames.joined(separator: " ")) git ssh scp curl tar gzip unzip zip base64 python3 pip3 node npm make jq; do
              if command -v "$tool" >/dev/null 2>&1; then echo "ok  command:$tool $(command -v "$tool")"; else echo "miss command:$tool"; fi
            done
            if command -v git >/dev/null 2>&1; then
              tmp=$(mktemp -d /tmp/litter-git.XXXXXX)
              if git -C "$tmp" init >/dev/null 2>&1; then echo "ok  git temp files"; else echo "bad git temp files"; ok=0; fi
              rm -rf "$tmp"
            else
              echo "bad git temp files (git not installed)"; ok=0
            fi
            exit $((ok == 1 ? 0 : 1))
            """
        )
        let status = checks.exitCode == 0 ? "doctor-ok" : "doctor-failed"
        return BuildKitCommandResult(exitCode: Int(checks.exitCode), status: status, log: "Repair output:\n\(repair.output)\nChecks:\n\(checks.output)")
    }

    private func envReport() async -> BuildKitCommandResult {
        let report = await IshFS.run(
            """
            set +e
            echo "Litter fakefs environment"
            echo "kernel=$(uname -a 2>/dev/null)"
            echo "cwd=$(pwd)"
            echo "PATH=$PATH"
            echo
            echo "Core devices:"
            ls -l /dev/null /dev/random /dev/urandom 2>/dev/null
            echo
            echo "Storage:"
            df -h / /root /tmp 2>/dev/null
            echo
            echo "Packages:"
            if command -v apk >/dev/null 2>&1; then apk info | sort | sed -n '1,120p'; else echo "apk missing"; fi
            echo
            echo "Tool versions:"
            buildkit_shims=" \(Self.commandNames.joined(separator: " ")) "
            for tool in \(Self.commandNames.joined(separator: " ")) git ssh scp curl tar gzip unzip zip base64 python3 pip3 node npm make jq; do
              if command -v "$tool" >/dev/null 2>&1; then
                tool_path="$(command -v "$tool")"
                case "$buildkit_shims" in
                  *" $tool "*) echo "$tool: $tool_path (Litter BuildKit shim; version check skipped inside env-report)" ;;
                  *) printf '%s: ' "$tool"; "$tool" --version 2>&1 | head -n 1 ;;
                esac
              else
                echo "$tool: missing"
              fi
            done
            """
        )
        return BuildKitCommandResult(exitCode: Int(report.exitCode), status: "env-report", log: report.output)
    }

    private func devBootstrap() async -> BuildKitCommandResult {
        await IshFS.repairCoreDevices()
        let bootstrap = await IshFS.run(
            """
            set -eu
            mkdir -p /root/bin /root/litter /root/projects /root/.cache/litter /root/.litter/buildkit/requests /root/.litter/builds /tmp
            chmod 1777 /tmp /var/tmp 2>/dev/null || true
            if command -v apk >/dev/null 2>&1; then
              apk update || true
              apk add --no-cache git openssh-client curl tar gzip xz unzip zip python3 py3-pip nodejs npm ca-certificates coreutils findutils grep sed gawk ripgrep make clang llvm lld binutils build-base jq || true
            fi
            git config --global init.defaultBranch main 2>/dev/null || true
            git config --global advice.detachedHead false 2>/dev/null || true
            cat > /root/.litter-fakefs-version <<'EOF'
            litter-fakefs-dev-bootstrap=1
            layout=/root,/root/litter,/root/projects,/root/.litter/builds,/root/.cache/litter,/usr/local/bin
            EOF
            echo "Bootstrap complete."
            """
        )
        let status = bootstrap.exitCode == 0 ? "bootstrap-ok" : "bootstrap-warning"
        return BuildKitCommandResult(exitCode: Int(bootstrap.exitCode), status: status, log: bootstrap.output)
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

        let staging = Self.stageSwiftSourceForNativeDriver(fakefsPath: path, source: source, buildDir: buildDir)
        log += staging.log

        let status = await status()
        guard status.isReadyForNativeBuilds else {
            log += "\nBlocked: BuildKit is not ready for native Swift builds.\n"
            log += Self.missingAssetSummary(status)
            return BuildKitCommandResult(exitCode: 78, status: "toolchain-missing", log: log)
        }
        return await nativeBuildCommand(command: "litter-swift-check", args: args, cwd: cwd, buildDir: buildDir, prelude: log, staging: staging)
    }

    private func swiftSelfTest(cwd: String, buildDir: String) async -> BuildKitCommandResult {
        let root = "\(buildDir)/toolchain-selftest"
        let swiftPath = "\(root)/hello.swift"
        let swiftOutputPath = "\(root)/hello-swift"
        let uiSwiftPath = "\(root)/UIKitSmoke.swift"
        let cPath = "\(root)/hello.c"
        let cxxPath = "\(root)/hello.cpp"
        let objcPath = "\(root)/hello.m"
        let objcxxPath = "\(root)/hello.mm"
        let projectDir = "\(root)/HelloUIKit"
        let projectSources = "\(projectDir)/Sources"
        let projectManifest = "\(projectDir)/LitterBuild.json"
        var artifacts: [NativeDriverArtifact] = []
        var log = """
        Litter full iOS toolchain self-test
        Root: \(root)
        Checks: Swift typecheck, Swift compile, UIKit import, C, C++, Objective-C, Objective-C++, unsigned UIKit IPA packaging.

        """

        func record(_ label: String, _ result: BuildKitCommandResult) -> Bool {
            log += "\n== \(label) ==\n"
            log += "status=\(result.status) exitCode=\(result.exitCode)\n"
            log += result.log
            artifacts.append(contentsOf: result.artifacts)
            return result.exitCode == 0
        }

        do {
            _ = await IshFS.run("rm -rf \(IshFS.shellQuote(root)) && mkdir -p \(IshFS.shellQuote(root)) \(IshFS.shellQuote(projectSources))")
            try await IshFS.writeTextFile(path: swiftPath, text: """
            print("Swift is running on device")
            """)
            try await IshFS.writeTextFile(path: uiSwiftPath, text: """
            import UIKit

            final class LitterUIKitSmokeViewController: UIViewController {
                override func viewDidLoad() {
                    super.viewDidLoad()
                    view.backgroundColor = .systemBackground
                }
            }
            """)
            try await IshFS.writeTextFile(path: cPath, text: """
            #include <stdint.h>
            int litter_c_add(int a, int b) { return a + b; }
            """)
            try await IshFS.writeTextFile(path: cxxPath, text: """
            #include <vector>
            int litter_cxx_sum(void) {
                std::vector<int> values = {1, 2, 3};
                int total = 0;
                for (int value : values) { total += value; }
                return total;
            }
            """)
            try await IshFS.writeTextFile(path: objcPath, text: """
            #import <Foundation/Foundation.h>
            @interface LitterObjCSmoke : NSObject
            @end
            @implementation LitterObjCSmoke
            @end
            int litter_objc_smoke(void) {
                @autoreleasepool { return (int)NSStringFromClass([LitterObjCSmoke class]).length; }
            }
            """)
            try await IshFS.writeTextFile(path: objcxxPath, text: """
            #import <Foundation/Foundation.h>
            #include <vector>
            int litter_objcxx_smoke(void) {
                std::vector<int> values = {1, 2, 3};
                @autoreleasepool { return (int)(values.size() + @"ok".length); }
            }
            """)
            try await IshFS.writeTextFile(path: "\(projectSources)/App.swift", text: """
            import UIKit

            @main
            final class AppDelegate: UIResponder, UIApplicationDelegate {
                var window: UIWindow?

                func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
                    let window = UIWindow(frame: UIScreen.main.bounds)
                    let viewController = UIViewController()
                    viewController.view.backgroundColor = .systemBackground
                    let label = UILabel()
                    label.text = "Hello from Litter"
                    label.font = .systemFont(ofSize: 28, weight: .semibold)
                    label.textAlignment = .center
                    label.translatesAutoresizingMaskIntoConstraints = false
                    viewController.view.addSubview(label)
                    NSLayoutConstraint.activate([
                        label.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
                        label.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor)
                    ])
                    window.rootViewController = viewController
                    self.window = window
                    window.makeKeyAndVisible()
                    return true
                }
            }
            """)
            try await IshFS.writeTextFile(path: projectManifest, text: """
            {
              "schemaVersion": 1,
              "name": "HelloUIKit",
              "bundleIdentifier": "com.sigkitten.litter.selftest.hellouikit",
              "deploymentTarget": "18.0",
              "sdk": "iphoneos",
              "product": "app",
              "entrypoint": "Sources/App.swift",
              "sources": ["Sources"],
              "resources": [],
              "output": "HelloUIKit.ipa"
            }
            """)
        } catch {
            log += "Could not write self-test sources into fakefs: \(error.localizedDescription)\n"
            return BuildKitCommandResult(exitCode: 73, status: "toolchain-selftest-setup-failed", log: log, artifacts: artifacts)
        }

        let current = await status()
        guard current.isReadyForNativeBuilds else {
            log += "Blocked: BuildKit is not ready for native iOS builds.\n"
            log += Self.missingAssetSummary(current)
            return BuildKitCommandResult(exitCode: 78, status: "toolchain-missing", log: log, artifacts: artifacts)
        }

        let swiftCheckResult = await swiftCheck(args: swiftPath, cwd: cwd, buildDir: buildDir)
        guard record("Swift typecheck", swiftCheckResult) else {
            return BuildKitCommandResult(exitCode: swiftCheckResult.exitCode, status: "toolchain-selftest-failed", log: log, artifacts: artifacts)
        }

        let swiftCompileResult = await swiftcCompile(args: "\(swiftPath) -o \(swiftOutputPath)", cwd: cwd, buildDir: buildDir, compatibilityName: "litter-swift-selftest")
        guard record("Swift compile", swiftCompileResult) else {
            return BuildKitCommandResult(exitCode: swiftCompileResult.exitCode, status: "toolchain-selftest-failed", log: log, artifacts: artifacts)
        }
        guard await IshFS.exists(path: swiftOutputPath) else {
            log += "\nSwift compile did not export the fakefs artifact at \(swiftOutputPath).\n"
            return BuildKitCommandResult(exitCode: 74, status: "toolchain-selftest-export-failed", log: log, artifacts: artifacts)
        }

        let uiCheckResult = await swiftCheck(args: uiSwiftPath, cwd: cwd, buildDir: buildDir)
        guard record("Swift UIKit import", uiCheckResult) else {
            return BuildKitCommandResult(exitCode: uiCheckResult.exitCode, status: "toolchain-selftest-failed", log: log, artifacts: artifacts)
        }

        let cResult = await clangCompatibility(command: "clang", args: "\(cPath) -c -o \(root)/hello-c.o", cwd: cwd, buildDir: buildDir)
        guard record("C compile", cResult) else {
            return BuildKitCommandResult(exitCode: cResult.exitCode, status: "toolchain-selftest-failed", log: log, artifacts: artifacts)
        }

        let cxxResult = await clangCompatibility(command: "clang++", args: "\(cxxPath) -std=c++17 -c -o \(root)/hello-cxx.o", cwd: cwd, buildDir: buildDir)
        guard record("C++ compile", cxxResult) else {
            return BuildKitCommandResult(exitCode: cxxResult.exitCode, status: "toolchain-selftest-failed", log: log, artifacts: artifacts)
        }

        let objcResult = await clangCompatibility(command: "clang", args: "\(objcPath) -fobjc-arc -c -o \(root)/hello-objc.o", cwd: cwd, buildDir: buildDir)
        guard record("Objective-C compile", objcResult) else {
            return BuildKitCommandResult(exitCode: objcResult.exitCode, status: "toolchain-selftest-failed", log: log, artifacts: artifacts)
        }

        let objcxxResult = await clangCompatibility(command: "clang++", args: "\(objcxxPath) -std=c++17 -fobjc-arc -c -o \(root)/hello-objcxx.o", cwd: cwd, buildDir: buildDir)
        guard record("Objective-C++ compile", objcxxResult) else {
            return BuildKitCommandResult(exitCode: objcxxResult.exitCode, status: "toolchain-selftest-failed", log: log, artifacts: artifacts)
        }

        let ipaResult = await nativeBuildCommand(command: "litter-ipa-build", args: projectManifest, cwd: cwd, buildDir: buildDir)
        guard record("UIKit unsigned IPA package", ipaResult) else {
            return BuildKitCommandResult(exitCode: ipaResult.exitCode, status: "toolchain-selftest-failed", log: log, artifacts: artifacts)
        }
        let ipaPath = "\(projectDir)/HelloUIKit.ipa"
        guard await IshFS.exists(path: ipaPath) else {
            log += "\nIPA build completed but did not export \(ipaPath).\n"
            return BuildKitCommandResult(exitCode: 74, status: "toolchain-selftest-ipa-export-failed", log: log, artifacts: artifacts)
        }

        log += "\nSelf-test passed: Swift, UIKit imports, C, C++, Objective-C, Objective-C++, and unsigned IPA packaging all completed. Produced iOS Mach-O artifacts are not meant to execute inside iSH; install the IPA through a signer to run it.\n"
        return BuildKitCommandResult(exitCode: 0, status: "toolchain-selftest-ok", log: log, artifacts: artifacts)
    }

    private func swiftCompatibility(args: String, cwd: String, buildDir: String) async -> BuildKitCommandResult {
        let tokens = Self.shellWords(args)
        guard let first = tokens.first else {
            return BuildKitCommandResult(exitCode: 64, status: "swift-usage", log: Self.swiftCompatibilityUsage())
        }
        if ["--version", "-version", "version"].contains(first) {
            let status = await status()
            return BuildKitCommandResult(exitCode: 0, status: "swift-version", log: Self.compatibilityVersionLog(tool: "swift", status: status))
        }
        if ["--help", "-help", "help"].contains(first) {
            return BuildKitCommandResult(exitCode: 0, status: "swift-help", log: Self.swiftCompatibilityUsage())
        }
        if first == "build" {
            return await nativeBuildCommand(command: "litter-swift-build", args: Self.compatibilityProjectArgs(tokens: Array(tokens.dropFirst())), cwd: cwd, buildDir: buildDir)
        }
        if first == "test" {
            return await nativeBuildCommand(command: "litter-swift-test", args: Self.compatibilityProjectArgs(tokens: Array(tokens.dropFirst())), cwd: cwd, buildDir: buildDir)
        }
        if first == "run" {
            let prelude = "Litter swift run compatibility: building an iOS artifact. iSH cannot execute iOS Mach-O binaries.\n"
            return await nativeBuildCommand(command: "litter-swift-build", args: Self.compatibilityProjectArgs(tokens: Array(tokens.dropFirst())), cwd: cwd, buildDir: buildDir, prelude: prelude)
        }
        if first == "package" {
            return BuildKitCommandResult(exitCode: 64, status: "swift-package-unsupported", log: "Litter does not embed full SwiftPM yet. Use swift build/test with LitterBuild.json or litter-swift-build/litter-swift-test.\n")
        }
        if first.hasSuffix(".swift") {
            return await swiftCheck(args: args, cwd: cwd, buildDir: buildDir)
        }
        return BuildKitCommandResult(exitCode: 64, status: "swift-unsupported", log: "Litter's swift compatibility shim supports: --version, --help, swift <file.swift>, swift build, swift test, and swift run as build-only.\nUse litter-swift-check, litter-swift-build, or litter-swift-test for the canonical bot API.\n")
    }

    private func swiftcCompile(args: String, cwd: String, buildDir: String, compatibilityName: String) async -> BuildKitCommandResult {
        let tokens = Self.shellWords(args)
        if let first = tokens.first, ["--version", "-version", "version"].contains(first) {
            let status = await status()
            return BuildKitCommandResult(exitCode: 0, status: "swiftc-version", log: Self.compatibilityVersionLog(tool: compatibilityName, status: status))
        }
        if tokens.contains("--help") || tokens.contains("-help") || tokens.isEmpty {
            return BuildKitCommandResult(exitCode: tokens.isEmpty ? 64 : 0, status: "swiftc-help", log: Self.swiftcCompatibilityUsage())
        }
        guard let sourceToken = tokens.first(where: { $0.hasSuffix(".swift") }) else {
            return BuildKitCommandResult(exitCode: 64, status: "swiftc-missing-input", log: "Usage: swiftc path/to/File.swift -o output\n")
        }
        let sourcePath = sourceToken.hasPrefix("/") ? sourceToken : "\(cwd)/\(sourceToken)"
        let source = (try? await IshFS.readTextFile(path: sourcePath, maxBytes: 512_000)) ?? ""
        var log = "\(compatibilityName) compatibility shim\n"
        log += "Input: \(sourcePath)\n"
        log += "Backend: Litter BuildKit native Swift driver\n\n"
        log += Self.staticSwiftPreflight(source: source, path: sourcePath)
        let staging = Self.stageSwiftSourceForNativeDriver(fakefsPath: sourcePath, source: source, buildDir: buildDir)
        log += staging.log
        return await nativeBuildCommand(command: "litter-swiftc", args: args, cwd: cwd, buildDir: buildDir, prelude: log, staging: staging)
    }

    private func clangCompatibility(command: String, args: String, cwd: String, buildDir: String) async -> BuildKitCommandResult {
        let tokens = Self.shellWords(args)
        if tokens.contains("--version") || tokens.contains("-version") || tokens.contains("-v") {
            let status = await status()
            return BuildKitCommandResult(exitCode: 0, status: "clang-version", log: Self.compatibilityVersionLog(tool: command, status: status))
        }
        if tokens.contains("--help") || tokens.contains("-help") || tokens.isEmpty {
            return BuildKitCommandResult(exitCode: tokens.isEmpty ? 64 : 0, status: "clang-help", log: Self.clangCompatibilityUsage(tool: command))
        }
        guard let sourceToken = Self.firstInputToken(in: tokens, extensions: Self.cFamilySourceExtensions) else {
            return BuildKitCommandResult(exitCode: 64, status: "clang-missing-input", log: "Usage: \(command) path/to/File.c [-c] [-o output]\n")
        }
        let sourcePath = Self.resolveFakefsPath(sourceToken, cwd: cwd)
        let staging = await Self.stageFakefsFileForNativeDriver(fakefsPath: sourcePath, buildDir: buildDir, preferredName: "Input.\(URL(fileURLWithPath: sourcePath).pathExtension)")
        var log = "\(command) compatibility shim\n"
        log += "Input: \(sourcePath)\n"
        log += "Backend: Litter BuildKit Nyxian Clang driver\n\n"
        log += staging.log
        return await nativeBuildCommand(command: "litter-clang", args: args, cwd: cwd, buildDir: buildDir, prelude: log, staging: staging)
    }

    private func ldCompatibility(command: String, args: String, cwd: String, buildDir: String) async -> BuildKitCommandResult {
        let tokens = Self.shellWords(args)
        if tokens.contains("--version") || tokens.contains("-version") || tokens.contains("-v") {
            let status = await status()
            return BuildKitCommandResult(exitCode: 0, status: "ld-version", log: Self.compatibilityVersionLog(tool: command, status: status))
        }
        if tokens.contains("--help") || tokens.contains("-help") || tokens.isEmpty {
            return BuildKitCommandResult(exitCode: tokens.isEmpty ? 64 : 0, status: "ld-help", log: Self.ldCompatibilityUsage(tool: command))
        }
        guard let inputToken = Self.firstInputToken(in: tokens, extensions: Self.linkInputExtensions) else {
            return BuildKitCommandResult(exitCode: 64, status: "ld-missing-input", log: "Usage: \(command) input.o -o output\n")
        }
        let inputPath = Self.resolveFakefsPath(inputToken, cwd: cwd)
        let staging = await Self.stageFakefsFileForNativeDriver(fakefsPath: inputPath, buildDir: buildDir, preferredName: URL(fileURLWithPath: inputPath).lastPathComponent)
        var log = "\(command) compatibility shim\n"
        log += "Input: \(inputPath)\n"
        log += "Backend: Litter BuildKit Nyxian linker path\n\n"
        log += staging.log
        return await nativeBuildCommand(command: "litter-ld", args: args, cwd: cwd, buildDir: buildDir, prelude: log, staging: staging)
    }

    private func xcrunCompatibility(args: String, cwd: String, buildDir: String) async -> BuildKitCommandResult {
        let tokens = Self.shellWords(args)
        if tokens.isEmpty || tokens.contains("--help") || tokens.contains("-help") {
            return BuildKitCommandResult(exitCode: tokens.isEmpty ? 64 : 0, status: "xcrun-help", log: Self.xcrunCompatibilityUsage())
        }
        if tokens.contains("--version") || tokens.contains("-version") {
            let current = await status()
            return BuildKitCommandResult(exitCode: 0, status: "xcrun-version", log: Self.compatibilityVersionLog(tool: "xcrun", status: current))
        }
        if tokens.contains("--show-sdk-path") || tokens.contains("-show-sdk-path") {
            return BuildKitCommandResult(exitCode: 0, status: "xcrun-sdk-path", log: "\(Self.sdkRoot.path)\n")
        }
        if let index = tokens.firstIndex(where: { $0 == "--find" || $0 == "-find" }), index + 1 < tokens.count {
            let tool = tokens[index + 1]
            if Self.commandNames.contains(tool) {
                return BuildKitCommandResult(exitCode: 0, status: "xcrun-find-ok", log: "/usr/local/bin/\(tool)\n")
            }
            if let path = await Self.firstFakefsExecutablePath(tool) {
                return BuildKitCommandResult(exitCode: 0, status: "xcrun-find-ok", log: "\(path)\n")
            }
            return BuildKitCommandResult(exitCode: 72, status: "xcrun-find-missing", log: "xcrun: could not find tool \(tool) in Litter BuildKit or fakefs.\n")
        }
        if let invocation = Self.xcrunToolInvocation(tokens: tokens) {
            let forwardedArgs = invocation.args.map(IshFS.shellQuote).joined(separator: " ")
            return await handle(command: invocation.tool, args: forwardedArgs, cwd: cwd, buildDir: buildDir)
        }
        return BuildKitCommandResult(exitCode: 64, status: "xcrun-unsupported", log: Self.xcrunCompatibilityUsage())
    }

    private func plutilCompatibility(args: String, cwd: String) async -> BuildKitCommandResult {
        let tokens = Self.shellWords(args)
        if tokens.isEmpty || tokens.contains("--help") || tokens.contains("-help") {
            return BuildKitCommandResult(exitCode: tokens.isEmpty ? 64 : 0, status: "plutil-help", log: Self.plutilCompatibilityUsage())
        }
        guard let inputToken = Self.plutilInputToken(tokens) else {
            return BuildKitCommandResult(exitCode: 64, status: "plutil-missing-input", log: "Usage: plutil -lint Info.plist | plutil -convert xml1|json [-o output] Info.plist\n")
        }
        let inputPath = Self.resolveFakefsPath(inputToken, cwd: cwd)
        do {
            let data = try await IshFS.readFileData(path: inputPath, maxBytes: 16_000_000)
            var format = PropertyListSerialization.PropertyListFormat.xml
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
            if tokens.contains("-lint") {
                return BuildKitCommandResult(exitCode: 0, status: "plutil-lint-ok", log: "\(inputPath): OK\n")
            }
            guard let convertIndex = tokens.firstIndex(of: "-convert"), convertIndex + 1 < tokens.count else {
                return BuildKitCommandResult(exitCode: 64, status: "plutil-unsupported", log: Self.plutilCompatibilityUsage())
            }
            let outputData: Data
            switch tokens[convertIndex + 1] {
            case "xml1":
                outputData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            case "json":
                guard JSONSerialization.isValidJSONObject(plist) else {
                    return BuildKitCommandResult(exitCode: 65, status: "plutil-json-unsupported", log: "\(inputPath): plist root cannot be represented as JSON.\n")
                }
                outputData = try JSONSerialization.data(withJSONObject: plist, options: [.prettyPrinted, .sortedKeys])
            default:
                return BuildKitCommandResult(exitCode: 64, status: "plutil-format-unsupported", log: "Supported plutil conversion formats: xml1, json.\n")
            }
            let outputPath = Self.plutilOutputPath(tokens, inputPath: inputPath, cwd: cwd)
            if outputPath == "-" {
                return BuildKitCommandResult(exitCode: 0, status: "plutil-convert-ok", log: String(data: outputData, encoding: .utf8) ?? "")
            }
            try await IshFS.writeFile(path: outputPath, data: outputData, replaceExisting: true)
            return BuildKitCommandResult(exitCode: 0, status: "plutil-convert-ok", log: "Wrote \(outputPath)\n")
        } catch {
            return BuildKitCommandResult(exitCode: 65, status: "plutil-failed", log: "\(inputPath): \(error.localizedDescription)\n")
        }
    }

    private func passThroughTool(command: String, args: String) async -> BuildKitCommandResult {
        let quotedArgs = Self.shellWords(args).map(IshFS.shellQuote).joined(separator: " ")
        let candidates = Self.passThroughCandidates(for: command).map(IshFS.shellQuote).joined(separator: " ")
        let result = await IshFS.run(
            """
            set -u
            for candidate in \(candidates); do
              if [ -x "$candidate" ]; then
                exec "$candidate" \(quotedArgs)
              fi
            done
            echo "\(command) is not available in fakefs. Run litter-dev-bootstrap to install iSH utility packages, or use the BuildKit native compiler commands for iOS artifacts."
            exit 127
            """
        )
        let status = result.exitCode == 0 ? "\(command)-ok" : "\(command)-unavailable"
        return BuildKitCommandResult(exitCode: Int(result.exitCode), status: status, log: result.output)
    }

    private func xcodebuildCompatibility(args: String, cwd: String, buildDir: String) async -> BuildKitCommandResult {
        let tokens = Self.shellWords(args)
        if tokens.contains("-version") || tokens.contains("--version") {
            let status = await status()
            return BuildKitCommandResult(exitCode: 0, status: "xcodebuild-version", log: Self.compatibilityVersionLog(tool: "xcodebuild", status: status))
        }
        if tokens.contains("-help") || tokens.contains("--help") {
            return BuildKitCommandResult(exitCode: 0, status: "xcodebuild-help", log: Self.xcodebuildCompatibilityUsage())
        }
        if tokens.contains("-showsdks") {
            return BuildKitCommandResult(exitCode: 0, status: "xcodebuild-sdks", log: Self.xcodebuildSDKList())
        }
        if Self.tokensRequestSimulator(tokens) {
            return BuildKitCommandResult(exitCode: 64, status: "simulator-unsupported", log: "Litter BuildKit is iOS-device only. Use -sdk iphoneos and an arm64 iOS deployment target; simulator destinations are not available on device.\n")
        }
        if tokens.contains("-list") {
            return BuildKitCommandResult(exitCode: 0, status: "xcodebuild-list", log: Self.xcodebuildListLog(projectArgs: Self.compatibilityProjectArgs(tokens: tokens)))
        }
        if tokens.contains("-showBuildSettings") {
            return BuildKitCommandResult(exitCode: 0, status: "xcodebuild-settings", log: Self.xcodebuildSettingsLog(projectArgs: Self.compatibilityProjectArgs(tokens: tokens)))
        }
        let projectArgs = Self.compatibilityProjectArgs(tokens: tokens)
        if tokens.contains("archive") {
            return await nativeBuildCommand(command: "litter-ipa-build", args: projectArgs, cwd: cwd, buildDir: buildDir)
        }
        if tokens.contains("test") {
            return await nativeBuildCommand(command: "litter-swift-test", args: projectArgs, cwd: cwd, buildDir: buildDir)
        }
        if tokens.contains("clean") {
            return BuildKitCommandResult(exitCode: 0, status: "xcodebuild-clean-ok", log: "Litter xcodebuild compatibility shim: clean is a no-op for staged BuildKit jobs.\n")
        }
        return await nativeBuildCommand(command: "litter-swift-build", args: projectArgs, cwd: cwd, buildDir: buildDir)
    }

    private func xcodeSelectCompatibility(args: String) async -> BuildKitCommandResult {
        let tokens = Self.shellWords(args)
        if tokens.isEmpty || tokens.contains("-p") || tokens.contains("--print-path") {
            return BuildKitCommandResult(exitCode: 0, status: "xcode-select-path", log: "\(Self.toolchainRoot.path)\n")
        }
        if tokens.contains("--version") || tokens.contains("-version") {
            return BuildKitCommandResult(exitCode: 0, status: "xcode-select-version", log: "xcode-select compatibility shim for Litter BuildKit\n")
        }
        if tokens.contains("--help") || tokens.contains("-help") {
            return BuildKitCommandResult(exitCode: 0, status: "xcode-select-help", log: "Supported: xcode-select -p, xcode-select --print-path, xcode-select --version\n")
        }
        return BuildKitCommandResult(exitCode: 64, status: "xcode-select-unsupported", log: "Litter's xcode-select shim only reports the on-device BuildKit developer path.\n")
    }

    private func codeCompatibility(args: String, cwd: String) -> BuildKitCommandResult {
        let target = Self.shellWords(args).first ?? cwd
        return BuildKitCommandResult(exitCode: 0, status: "code-compat", log: "Litter code compatibility shim\nTarget: \(target)\nThis IPA does not embed VS Code. Use Litter's file browser/editor or bot file tools for edits, then build with litter-swift-check, litter-swift-build, or litter-ipa-build.\n")
    }

    private func nativeBuildCommand(command: String, args: String, cwd: String, buildDir: String, prelude: String = "", staging providedStaging: BuildKitHostStaging? = nil) async -> BuildKitCommandResult {
        let staging: BuildKitHostStaging
        if let providedStaging {
            staging = providedStaging
        } else {
            staging = await stageProjectForNativeDriver(command: command, args: args, cwd: cwd, buildDir: buildDir)
        }
        var fullPrelude = prelude
        if providedStaging == nil {
            fullPrelude += staging.log
        }
        let current = await status()
        guard current.isReadyForNativeBuilds else {
            fullPrelude += "\(command) is routed through Litter BuildKit.\n"
            fullPrelude += Self.missingAssetSummary(current)
            return BuildKitCommandResult(exitCode: 78, status: "toolchain-missing", log: fullPrelude)
        }
        guard let result = Self.runNativeDriver(command: command, args: args, cwd: cwd, buildDir: buildDir, staging: staging) else {
            fullPrelude += "Native BuildKit assets are present, but the private native driver did not expose litter_buildkit_run_json.\n"
            fullPrelude += "Embed signed CoreCompiler.framework, LitterBuildKitNative.framework, and compiler support dylibs in the private sideload IPA.\n"
            return BuildKitCommandResult(exitCode: 78, status: "adapter-missing", log: fullPrelude)
        }
        let artifactLog = await publishArtifacts(result.artifacts, buildDir: buildDir)
        let resultLog = result.log + artifactLog
        if fullPrelude.isEmpty {
            return BuildKitCommandResult(exitCode: result.exitCode, status: result.status, log: resultLog, artifacts: result.artifacts)
        }
        return BuildKitCommandResult(exitCode: result.exitCode, status: result.status, log: fullPrelude + "\n" + resultLog, artifacts: result.artifacts)
    }

    private func publishArtifacts(_ artifacts: [NativeDriverArtifact], buildDir: String) async -> String {
        guard !artifacts.isEmpty else { return "" }
        var log = "\nArtifact export:\n"
        for artifact in artifacts {
            let hostURL = URL(fileURLWithPath: artifact.hostPath)
            let reportedFakefsPath = artifact.fakefsPath?.isEmpty == false ? artifact.fakefsPath! : ""
            let fakefsPath: String
            if reportedFakefsPath.isEmpty || Self.isNativeHostPath(reportedFakefsPath) {
                let fallbackName = reportedFakefsPath.isEmpty ? hostURL.lastPathComponent : (reportedFakefsPath as NSString).lastPathComponent
                fakefsPath = "\(buildDir)/\(fallbackName)"
            } else {
                fakefsPath = reportedFakefsPath
            }
            let fakefsParent = (fakefsPath as NSString).deletingLastPathComponent
            if !fakefsParent.isEmpty && fakefsParent != fakefsPath {
                _ = await IshFS.run("mkdir -p \(IshFS.shellQuote(fakefsParent))")
            }
            do {
                try await IshFS.writeFile(path: fakefsPath, sourceURL: hostURL, replaceExisting: true)
                log += "- Published \(hostURL.lastPathComponent) -> \(fakefsPath)\n"
            } catch {
                log += "- Failed to publish \(hostURL.path) to fakefs: \(error.localizedDescription)\n"
            }
        }
        return log
    }

    private func stageProjectForNativeDriver(command: String, args: String, cwd: String, buildDir: String) async -> BuildKitHostStaging {
        guard ["litter-swift-build", "litter-swift-test", "litter-ipa-build", "litter-ipa-package"].contains(command) else {
            return BuildKitHostStaging(log: "", hostWorkDir: nil, hostProjectPath: nil, hostInputPath: nil, fakefsProjectPath: nil)
        }
        let hostRoot = Self.hostJobRoot(buildDir: buildDir)
        guard let first = Self.shellWords(args).first else {
            return BuildKitHostStaging(log: "BuildKit project preflight: missing LitterBuild.json path.\n", hostWorkDir: hostRoot.path, hostProjectPath: nil, hostInputPath: nil, fakefsProjectPath: nil)
        }
        let projectPath = first.hasPrefix("/") ? first : "\(cwd)/\(first)"
        var log = "BuildKit project preflight\nProject: \(projectPath)\n"
        guard let manifestText = try? await IshFS.readTextFile(path: projectPath, maxBytes: 256_000), let data = manifestText.data(using: .utf8), let manifest = try? JSONDecoder().decode(LitterBuildProjectManifest.self, from: data) else {
            log += "- Could not read or decode LitterBuild.json. Native driver will receive the original request only.\n"
            return BuildKitHostStaging(log: log, hostWorkDir: hostRoot.path, hostProjectPath: nil, hostInputPath: nil, fakefsProjectPath: projectPath)
        }

        let fakefsProjectDir = Self.normalizedFakefsPath((projectPath as NSString).deletingLastPathComponent)
        let hostProjectPath = hostRoot.appendingPathComponent("LitterBuild.json")
        let stagedManifest = Self.stagedProjectManifestForNativeDriver(manifest, fakefsProjectDir: fakefsProjectDir)
        do {
            let hostManifestData = try JSONEncoder().encode(stagedManifest)
            try FileManager.default.createDirectory(at: hostRoot, withIntermediateDirectories: true, attributes: nil)
            try hostManifestData.write(to: hostProjectPath, options: .atomic)
        } catch {
            log += "- Could not stage project manifest for native driver: \(error.localizedDescription)\n"
            return BuildKitHostStaging(log: log, hostWorkDir: hostRoot.path, hostProjectPath: nil, hostInputPath: nil, fakefsProjectPath: projectPath)
        }

        var copied = 0
        var skipped = 0
        let roots = Self.stagedProjectRootMappings(for: manifest, fakefsProjectDir: fakefsProjectDir)
        for mapping in roots.sorted(by: { $0.fakefsRoot < $1.fakefsRoot }) {
            let root = mapping.fakefsRoot
            let rootIsDirectory = await IshFS.run("[ -d \(IshFS.shellQuote(root)) ]").exitCode == 0
            let result = await IshFS.run("if [ -d \(IshFS.shellQuote(root)) ]; then find \(IshFS.shellQuote(root)) -type f; elif [ -f \(IshFS.shellQuote(root)) ]; then printf '%s\\n' \(IshFS.shellQuote(root)); fi")
            guard result.exitCode == 0 else { skipped += 1; continue }
            for file in result.output.split(separator: "\n").map(String.init) {
                let relative = rootIsDirectory ? Self.joinRelativePath(mapping.stagedRoot, Self.relativeFakefsPath(file, base: root)) : mapping.stagedRoot
                let hostFile = hostRoot.appendingPathComponent(relative)
                do {
                    let data = try await IshFS.readFileData(path: file, maxBytes: 64_000_000)
                    try FileManager.default.createDirectory(at: hostFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                    try data.write(to: hostFile, options: .atomic)
                    copied += 1
                } catch {
                    skipped += 1
                }
            }
        }
        log += "- Manifest: \(manifest.name) \(manifest.bundleIdentifier) deployment \(manifest.deploymentTarget)\n"
        log += "- Staged host work dir: \(hostRoot.path)\n"
        log += "- Staged files: \(copied); skipped large/unreadable files: \(skipped)\n"
        return BuildKitHostStaging(log: log, hostWorkDir: hostRoot.path, hostProjectPath: hostProjectPath.path, hostInputPath: nil, fakefsProjectPath: projectPath)
    }

    private static func stageSwiftSourceForNativeDriver(fakefsPath: String, source: String, buildDir: String) -> BuildKitHostStaging {
        let hostRoot = hostJobRoot(buildDir: buildDir)
        let hostInput = hostRoot.appendingPathComponent("Input.swift")
        var log = ""
        do {
            try FileManager.default.createDirectory(at: hostRoot, withIntermediateDirectories: true, attributes: nil)
            try Data(source.utf8).write(to: hostInput, options: .atomic)
            log += "Native staging: \(fakefsPath) -> \(hostInput.path)\n"
        } catch {
            log += "Native staging failed: \(error.localizedDescription)\n"
        }
        return BuildKitHostStaging(log: log, hostWorkDir: hostRoot.path, hostProjectPath: nil, hostInputPath: hostInput.path, fakefsProjectPath: fakefsPath)
    }

    private static func stageFakefsFileForNativeDriver(fakefsPath: String, buildDir: String, preferredName: String) async -> BuildKitHostStaging {
        let hostRoot = hostJobRoot(buildDir: buildDir)
        let safeName = sanitizedHostFileName(preferredName.isEmpty ? URL(fileURLWithPath: fakefsPath).lastPathComponent : preferredName)
        let hostInput = hostRoot.appendingPathComponent(safeName)
        var log = ""
        do {
            let data = try await IshFS.readFileData(path: fakefsPath, maxBytes: 64_000_000)
            try FileManager.default.createDirectory(at: hostRoot, withIntermediateDirectories: true, attributes: nil)
            try data.write(to: hostInput, options: .atomic)
            log += "Native staging: \(fakefsPath) -> \(hostInput.path)\n"
        } catch {
            log += "Native staging failed: \(error.localizedDescription)\n"
        }
        return BuildKitHostStaging(log: log, hostWorkDir: hostRoot.path, hostProjectPath: nil, hostInputPath: hostInput.path, fakefsProjectPath: fakefsPath)
    }

    private static func sanitizedHostFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Input" : trimmed
        let cleaned = fallback
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned == "." || cleaned == ".." ? "Input" : cleaned
    }

    private static func hostJobRoot(buildDir: String) -> URL {
        let id = URL(fileURLWithPath: buildDir).lastPathComponent.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
        return buildKitRoot.appendingPathComponent("Jobs/\(id)", isDirectory: true)
    }

    static func stagedProjectManifestForNativeDriver(_ manifest: LitterBuildProjectManifest, fakefsProjectDir: String) -> LitterBuildProjectManifest {
        var staged = manifest
        staged.sources = manifest.sources.map { stagedProjectRelativePath($0, fakefsProjectDir: fakefsProjectDir) }
        staged.resources = manifest.resources?.map { stagedProjectRelativePath($0, fakefsProjectDir: fakefsProjectDir) }
        staged.entitlements = manifest.entitlements.map { stagedProjectRelativePath($0, fakefsProjectDir: fakefsProjectDir) }
        staged.entrypoint = manifest.entrypoint.map { stagedProjectRelativePath($0, fakefsProjectDir: fakefsProjectDir) }
        return staged
    }

    private static func stagedProjectRootMappings(for manifest: LitterBuildProjectManifest, fakefsProjectDir: String) -> [(fakefsRoot: String, stagedRoot: String)] {
        let paths = manifest.sources + (manifest.resources ?? []) + [manifest.entitlements, manifest.entrypoint].compactMap { $0 }
        var seen: Set<String> = []
        var mappings: [(fakefsRoot: String, stagedRoot: String)] = []
        for path in paths {
            let fakefsRoot = fakefsAbsolutePath(path, fakefsProjectDir: fakefsProjectDir)
            guard seen.insert(fakefsRoot).inserted else { continue }
            mappings.append((fakefsRoot: fakefsRoot, stagedRoot: stagedProjectRelativePath(path, fakefsProjectDir: fakefsProjectDir)))
        }
        return mappings
    }

    private static func stagedProjectRelativePath(_ path: String, fakefsProjectDir: String) -> String {
        let projectDir = normalizedFakefsPath(fakefsProjectDir)
        let absolute = fakefsAbsolutePath(path, fakefsProjectDir: projectDir)
        let normalizedBase = projectDir.hasSuffix("/") ? projectDir : projectDir + "/"
        if absolute.hasPrefix(normalizedBase) {
            return String(absolute.dropFirst(normalizedBase.count))
        }
        if absolute == projectDir { return "." }
        let external = absolute.split(separator: "/").map(String.init).joined(separator: "/")
        return "_external/" + (external.isEmpty ? "root" : external)
    }

    private static func fakefsAbsolutePath(_ path: String, fakefsProjectDir: String) -> String {
        if path.hasPrefix("/") { return normalizedFakefsPath(path) }
        return normalizedFakefsPath((fakefsProjectDir as NSString).appendingPathComponent(path))
    }

    private static func normalizedFakefsPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func joinRelativePath(_ base: String, _ child: String) -> String {
        if base.isEmpty { return child }
        if child.isEmpty { return base }
        if base == "." { return child }
        if base.hasSuffix("/") { return base + child }
        return base + "/" + child
    }

    private static func relativeFakefsPath(_ path: String, base: String) -> String {
        let normalizedBase = base.hasSuffix("/") ? base : base + "/"
        if path.hasPrefix(normalizedBase) { return String(path.dropFirst(normalizedBase.count)) }
        return URL(fileURLWithPath: path).lastPathComponent
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

    private static func isNativeHostPath(_ path: String) -> Bool {
        path.hasPrefix(documentsRoot.path + "/") || path.hasPrefix(buildKitRoot.path + "/")
    }

    private static var buildKitRoot: URL {
        documentsRoot.appendingPathComponent("BuildKit", isDirectory: true)
    }

    private static var toolchainRoot: URL {
        buildKitRoot.appendingPathComponent("Toolchains/Nyxian", isDirectory: true)
    }

    private static var sdkRoot: URL {
        if let sdkPath = installedManifest?.toolchain.sdkPath, !sdkPath.isEmpty {
            return buildKitRoot.appendingPathComponent(sdkPath, isDirectory: true)
        }
        return defaultSDKRoot
    }

    private static var defaultSDKRoot: URL {
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
        guard let manifest = installedManifest else { return false }
        guard nativeCompilerAssetsInstalled,
              nativeDriverInstalled,
              nativeDriverLoadable,
              supportLibrariesInstalled,
              sdkInstalled,
              clangResourceDirInstalled,
              swiftResourceDirInstalled,
              cxxStandardLibraryHeadersInstalled,
              nativeRunnerInstalled else {
            return false
        }
        if let availableManifest = firstAvailableAssetCandidateManifest(), assetManifest(availableManifest, shouldReplace: manifest) {
            return false
        }
        return true
    }

    private static var nativeCompilerAssetsInstalled: Bool {
        fileExists(embeddedFrameworkURL(named: "CoreCompiler"))
    }

    private static var nativeDriverInstalled: Bool {
        fileExists(embeddedFrameworkURL(named: "LitterBuildKitNative"))
    }

    private static var nativeDriverLoadable: Bool {
        loadNativeDriver().handle != nil
    }

    private static var nativeRunnerInstalled: Bool {
        guard let runner = installedManifest?.toolchain.nativeRunner else { return true }
        return fileExists(buildKitRoot.appendingPathComponent(runner))
    }

    private static var supportLibrariesInstalled: Bool {
        embeddedSupportLibraryRoots().contains { root in
            guard let contents = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
                return false
            }
            return contents.contains { Self.isCompilerSupportLibrary($0) }
        }
    }

    private static var sdkInstalled: Bool {
        fileExists(sdkRoot.appendingPathComponent("SDKSettings.plist"))
    }

    private static var clangResourceRoot: URL {
        if let path = installedManifest?.toolchain.clangResourceDir, !path.isEmpty {
            return buildKitRoot.appendingPathComponent(path, isDirectory: true)
        }
        return toolchainRoot.appendingPathComponent("ClangResourceDir", isDirectory: true)
    }

    private static var swiftResourceRoot: URL {
        if let path = installedManifest?.toolchain.swiftResourceDir, !path.isEmpty {
            return buildKitRoot.appendingPathComponent(path, isDirectory: true)
        }
        let packaged = toolchainRoot.appendingPathComponent("SwiftResourceDir", isDirectory: true)
        if fileExists(packaged) { return packaged }
        let sdkSwift = sdkRoot.appendingPathComponent("usr/lib/swift", isDirectory: true)
        if fileExists(sdkSwift) { return sdkSwift }
        return packaged
    }

    private static var cxxStandardLibraryIncludeRoot: URL {
        if let path = installedManifest?.toolchain.cxxStandardLibraryIncludeDir, !path.isEmpty {
            return buildKitRoot.appendingPathComponent(path, isDirectory: true)
        }
        return toolchainRoot.appendingPathComponent("CxxStandardLibrary/include/c++/v1", isDirectory: true)
    }

    private static var clangResourceDirInstalled: Bool {
        fileExists(clangResourceRoot.appendingPathComponent("include/stdarg.h")) && fileExists(clangResourceRoot.appendingPathComponent("include/stdbool.h")) && fileExists(clangResourceRoot.appendingPathComponent("include/stddef.h"))
    }

    private static var swiftResourceDirInstalled: Bool {
        fileExists(swiftResourceRoot.appendingPathComponent("iphoneos")) || fileExists(swiftResourceRoot.appendingPathComponent("Swift.swiftmodule"))
    }

    private static var cxxStandardLibraryHeadersInstalled: Bool {
        fileExists(cxxStandardLibraryIncludeRoot.appendingPathComponent("vector"))
    }

    private static var nativeDriverURL: URL {
        toolchainRoot.appendingPathComponent("LitterBuildKitNative.framework/LitterBuildKitNative")
    }

    private static var sourceImportAvailable: Bool {
        sourceImportManifest != nil
    }

    private static var sourceImportManifest: BuildKitSourceImportManifest? {
        guard let url = Bundle.main.url(forResource: "nyxian-import-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BuildKitSourceImportManifest.self, from: data)
    }

    private static var embeddedFrameworksRoot: URL {
        Bundle.main.privateFrameworksURL ?? Bundle.main.bundleURL.appendingPathComponent("Frameworks", isDirectory: true)
    }

    private static func embeddedFrameworkURL(named name: String) -> URL {
        embeddedFrameworksRoot.appendingPathComponent("\(name).framework/\(name)")
    }

    private static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private enum AssetCandidateKind {
        case directory
        case zip
    }

    private struct AssetCandidate {
        var label: String
        var url: URL?
        var kind: AssetCandidateKind
    }

    private struct AvailableAssetCandidate {
        var candidate: AssetCandidate
        var url: URL
        var manifest: BuildKitAssetManifest
    }

    private static func assetCandidates() -> [AssetCandidate] {
        [
            AssetCandidate(label: "bundled BuildKitAssets directory", url: Bundle.main.url(forResource: "BuildKitAssets", withExtension: nil), kind: .directory),
            AssetCandidate(label: "Documents/BuildKitAssets directory", url: documentsRoot.appendingPathComponent("BuildKitAssets", isDirectory: true), kind: .directory),
            AssetCandidate(label: "Documents/Inbox/BuildKitAssets directory", url: documentsRoot.appendingPathComponent("Inbox/BuildKitAssets", isDirectory: true), kind: .directory),
            AssetCandidate(label: "bundled LitterBuildKitAssets.zip", url: Bundle.main.url(forResource: "LitterBuildKitAssets", withExtension: "zip"), kind: .zip),
            AssetCandidate(label: "Documents/LitterBuildKitAssets.zip", url: documentsRoot.appendingPathComponent("LitterBuildKitAssets.zip"), kind: .zip),
            AssetCandidate(label: "Documents/Inbox/LitterBuildKitAssets.zip", url: documentsRoot.appendingPathComponent("Inbox/LitterBuildKitAssets.zip"), kind: .zip)
        ]
    }

    private static func firstAvailableAssetCandidateDescription() -> String {
        guard let best = bestAvailableAssetCandidate() else { return "none" }
        return "\(best.candidate.label): \(best.url.path)"
    }

    private static func firstAvailableAssetCandidateManifest() -> BuildKitAssetManifest? {
        bestAvailableAssetCandidate()?.manifest
    }

    private static func availableAssetCandidates() -> [AvailableAssetCandidate] {
        assetCandidates().compactMap { candidate in
            guard let url = candidate.url, let manifest = assetManifest(for: candidate) else { return nil }
            return AvailableAssetCandidate(candidate: candidate, url: url, manifest: manifest)
        }
    }

    private static func bestAvailableAssetCandidate() -> AvailableAssetCandidate? {
        var best: AvailableAssetCandidate?
        for available in availableAssetCandidates() {
            guard let current = best else {
                best = available
                continue
            }
            if assetManifest(available.manifest, shouldReplace: current.manifest) {
                best = available
            }
        }
        return best
    }

    static func assetManifest(_ available: BuildKitAssetManifest, shouldReplace installed: BuildKitAssetManifest) -> Bool {
        guard available.bundleIdentifier == installed.bundleIdentifier else { return false }
        switch compareSDKVersion(available.sdkVersion, installed.sdkVersion) {
        case .orderedDescending:
            return true
        case .orderedAscending:
            return false
        case .orderedSame:
            guard let availableDate = assetManifestCreatedAtDate(available) else { return false }
            guard let installedDate = assetManifestCreatedAtDate(installed) else { return true }
            return availableDate > installedDate
        }
    }

    private static func compareSDKVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhsParts.count, rhsParts.count)
        for index in 0..<count {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left > right { return .orderedDescending }
            if left < right { return .orderedAscending }
        }
        return .orderedSame
    }

    private static func assetManifestCreatedAtDate(_ manifest: BuildKitAssetManifest) -> Date? {
        guard let createdAt = manifest.createdAt else { return nil }
        return ISO8601DateFormatter().date(from: createdAt)
    }

    private static func assetManifest(for candidate: AssetCandidate) -> BuildKitAssetManifest? {
        guard let url = candidate.url else { return nil }
        switch candidate.kind {
        case .directory:
            return directoryAssetManifest(url)
        case .zip:
            return zipAssetManifest(url)
        }
    }

    private static func directoryAssetManifest(_ url: URL) -> BuildKitAssetManifest? {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(BuildKitAssetManifest.self, from: data)
    }

    private static func zipAssetManifest(_ url: URL) -> BuildKitAssetManifest? {
        guard fileExists(url), let archive = Archive(url: url, accessMode: .read) else { return nil }
        for entry in archive {
            let normalized = entry.path.replacingOccurrences(of: "\\", with: "/")
            guard normalized == "manifest.json" || normalized.hasSuffix("/manifest.json") else { continue }
            var data = Data()
            do {
                _ = try archive.extract(entry) { chunk in
                    data.append(chunk)
                }
            } catch {
                return nil
            }
            return try? JSONDecoder().decode(BuildKitAssetManifest.self, from: data)
        }
        return nil
    }

    private static func assetAvailabilityReport() -> String {
        assetCandidates().map { candidate in
            guard let url = candidate.url else {
                return "- \(candidate.label): not found"
            }
            switch candidate.kind {
            case .directory:
                let manifest = url.appendingPathComponent("manifest.json")
                return "- \(candidate.label): \(manifest.path) \(fileExists(manifest) ? "present" : "missing")"
            case .zip:
                return "- \(candidate.label): \(url.path) \(fileExists(url) ? "present" : "missing")"
            }
        }.joined(separator: "\n")
    }

    private static func installFirstAvailableAssetDirectory() throws -> BuildKitAssetManifest {
        guard let best = bestAvailableAssetCandidate() else {
            throw NSError(domain: "LitterBuildKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected BuildKitAssets/manifest.json or LitterBuildKitAssets.zip in the app bundle, Documents, or Documents/Inbox.\n\(assetAvailabilityReport())"])
        }
        switch best.candidate.kind {
        case .directory:
            return try installAssetDirectory(best.url)
        case .zip:
            return try installAssetZip(best.url)
        }
    }

    private static func resolveAssetDirectory(_ url: URL) throws -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw NSError(domain: "LitterBuildKit", code: 6, userInfo: [NSLocalizedDescriptionKey: "Selected BuildKit asset path does not exist: \(url.path)"])
        }
        if isDirectory.boolValue {
            if fileExists(url.appendingPathComponent("manifest.json")) { return url }
            let nested = url.appendingPathComponent("BuildKitAssets", isDirectory: true)
            if fileExists(nested.appendingPathComponent("manifest.json")) { return nested }
        } else if url.lastPathComponent == "manifest.json" {
            return url.deletingLastPathComponent()
        }
        throw NSError(domain: "LitterBuildKit", code: 7, userInfo: [NSLocalizedDescriptionKey: "Select an expanded BuildKitAssets folder, its manifest.json, or LitterBuildKitAssets.zip."])
    }

    private static func installAssetZip(_ zipURL: URL) throws -> BuildKitAssetManifest {
        let fm = FileManager.default
        let extractionRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LitterBuildKitZip-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: extractionRoot) }
        try fm.createDirectory(at: extractionRoot, withIntermediateDirectories: true, attributes: nil)
        try extractAssetZip(zipURL, to: extractionRoot)
        let source = try findExtractedAssetDirectory(in: extractionRoot)
        return try installAssetDirectory(source)
    }

    private static func extractAssetZip(_ zipURL: URL, to destination: URL) throws {
        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            throw NSError(domain: "LitterBuildKit", code: 8, userInfo: [NSLocalizedDescriptionKey: "Could not open BuildKit asset ZIP: \(zipURL.lastPathComponent)"])
        }
        let fm = FileManager.default
        for entry in archive {
            let sanitized = try sanitizedZipEntryPath(entry.path)
            let output = destination.appendingPathComponent(sanitized)
            try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            do {
                _ = try archive.extract(entry, to: output)
            } catch {
                throw NSError(
                    domain: "LitterBuildKit",
                    code: 12,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Could not extract BuildKit ZIP entry \(entry.path): \(error.localizedDescription)",
                        NSUnderlyingErrorKey: error
                    ]
                )
            }
        }
    }

    private static func sanitizedZipEntryPath(_ path: String) throws -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let checkPath = normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized
        let components = checkPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !checkPath.isEmpty,
              !normalized.hasPrefix("/"),
              !components.contains(".."),
              !components.contains("") else {
            throw NSError(domain: "LitterBuildKit", code: 9, userInfo: [NSLocalizedDescriptionKey: "Unsafe path in BuildKit asset ZIP: \(path)"])
        }
        return normalized
    }

    private static func findExtractedAssetDirectory(in root: URL) throws -> URL {
        if fileExists(root.appendingPathComponent("manifest.json")) { return root }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw NSError(domain: "LitterBuildKit", code: 10, userInfo: [NSLocalizedDescriptionKey: "Could not inspect extracted BuildKit asset ZIP."])
        }
        for case let url as URL in enumerator where url.lastPathComponent == "manifest.json" {
            return url.deletingLastPathComponent()
        }
        throw NSError(domain: "LitterBuildKit", code: 11, userInfo: [NSLocalizedDescriptionKey: "Extracted BuildKit asset ZIP did not contain manifest.json."])
    }

    private static func installAssetDirectory(_ source: URL) throws -> BuildKitAssetManifest {
        let manifest = try validateAssetDirectory(source)
        let fm = FileManager.default
        let stage = documentsRoot.appendingPathComponent("BuildKit.installing", isDirectory: true)
        let previous = documentsRoot.appendingPathComponent("BuildKit.previous", isDirectory: true)
        try? fm.removeItem(at: stage)
        try? fm.removeItem(at: previous)
        try fm.createDirectory(at: stage.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
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
        try fm.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)
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
        guard let clangResourceDir = manifest.toolchain.clangResourceDir, !clangResourceDir.isEmpty else {
            throw NSError(domain: "LitterBuildKit", code: 13, userInfo: [NSLocalizedDescriptionKey: "BuildKit asset manifest is missing toolchain.clangResourceDir"])
        }
        guard let swiftResourceDir = manifest.toolchain.swiftResourceDir, !swiftResourceDir.isEmpty else {
            throw NSError(domain: "LitterBuildKit", code: 18, userInfo: [NSLocalizedDescriptionKey: "BuildKit asset manifest is missing toolchain.swiftResourceDir"])
        }
        guard let cxxIncludeDir = manifest.toolchain.cxxStandardLibraryIncludeDir, !cxxIncludeDir.isEmpty else {
            throw NSError(domain: "LitterBuildKit", code: 14, userInfo: [NSLocalizedDescriptionKey: "BuildKit asset manifest is missing toolchain.cxxStandardLibraryIncludeDir"])
        }
        guard manifest.swiftCompatibilityVersion?.isEmpty == false else {
            throw NSError(domain: "LitterBuildKit", code: 15, userInfo: [NSLocalizedDescriptionKey: "BuildKit asset manifest is missing swiftCompatibilityVersion"])
        }
        guard manifest.sdkSwiftVersion?.isEmpty == false else {
            throw NSError(domain: "LitterBuildKit", code: 16, userInfo: [NSLocalizedDescriptionKey: "BuildKit asset manifest is missing sdkSwiftVersion"])
        }
        let requiredCapabilities: Set<String> = ["clang-resource-dir", "cxx-stdlib-headers", "swift-resource-dir", "ui-framework-imports"]
        let missingCapabilities = requiredCapabilities.subtracting(Set(manifest.capabilities)).sorted()
        guard missingCapabilities.isEmpty else {
            throw NSError(domain: "LitterBuildKit", code: 17, userInfo: [NSLocalizedDescriptionKey: "BuildKit asset manifest is missing capabilities: \(missingCapabilities.joined(separator: ", "))"])
        }
        required.append(clangResourceDir)
        required.append("\(clangResourceDir)/include/stdarg.h")
        required.append("\(clangResourceDir)/include/stdbool.h")
        required.append("\(clangResourceDir)/include/stddef.h")
        required.append(swiftResourceDir)
        required.append("\(swiftResourceDir)/iphoneos")
        required.append(cxxIncludeDir)
        required.append("\(cxxIncludeDir)/vector")
        if let driver = manifest.toolchain.nativeDriverFramework { required.append(driver) }
        if let runner = manifest.toolchain.nativeRunner { required.append(runner) }
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
        try fileSHA256Hex(url)
    }

    nonisolated static func fileSHA256Hex(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct NativeDriverLoadResult {
        var handle: UnsafeMutableRawPointer?
        var diagnostics: [String]
    }

    private static var processSymbolHandle: UnsafeMutableRawPointer? {
        dlopen(nil, RTLD_NOW)
    }

    private static func consumeDLError() -> String? {
        guard let raw = dlerror() else { return nil }
        return String(cString: raw)
    }

    private static func openDynamicLibrary(_ url: URL, flags: Int32, diagnostics: inout [String]) -> UnsafeMutableRawPointer? {
        guard fileExists(url) else {
            diagnostics.append("missing \(url.path)")
            return nil
        }
        _ = consumeDLError()
        if let handle = dlopen(url.path, flags) {
            diagnostics.append("loaded \(url.path)")
            return handle
        }
        diagnostics.append("dlopen failed \(url.path): \(consumeDLError() ?? "unknown dyld error")")
        return nil
    }

    private static func embeddedSupportLibraryRoots() -> [URL] {
        let frameworks = embeddedFrameworksRoot
        return [
            frameworks,
            frameworks.appendingPathComponent("CoreCompilerSupportLibs", isDirectory: true)
        ]
    }

    private static func installedSupportLibraryRoots() -> [URL] {
        [toolchainRoot.appendingPathComponent("CoreCompilerSupportLibs", isDirectory: true)]
    }


    private static func preloadSupportLibraries(at root: URL, diagnostics: inout [String]) -> Bool {
        guard let supportLibraries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            diagnostics.append("support library directory missing or unreadable \(root.path)")
            return false
        }
        var pending = supportLibraries
            .filter { isCompilerSupportLibrary($0) }
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        var failures: [String: String] = [:]
        var loaded = false

        while !pending.isEmpty {
            var retry: [URL] = []
            var progressed = false
            for library in pending {
                _ = consumeDLError()
                if let handle = dlopen(library.path, RTLD_NOW | RTLD_GLOBAL) {
                    _ = handle
                    diagnostics.append("loaded \(library.path)")
                    loaded = true
                    progressed = true
                } else {
                    failures[library.path] = consumeDLError() ?? "unknown dyld error"
                    retry.append(library)
                }
            }
            pending = retry
            if !progressed { break }
        }

        for library in pending {
            diagnostics.append("dlopen failed \(library.path): \(failures[library.path] ?? "unknown dyld error")")
        }
        return loaded
    }

    private static func isCompilerSupportLibrary(_ url: URL) -> Bool {
        guard url.pathExtension == "dylib" else { return false }
        let name = url.lastPathComponent
        return name.hasPrefix("lib_Compiler") || name.hasPrefix("libLLVM") || name.hasPrefix("libllvm")
    }

    private static func preloadNativeDriverDependencies(diagnostics: inout [String]) {
        var loadedSupportLibrary = false
        for supportRoot in embeddedSupportLibraryRoots() {
            if preloadSupportLibraries(at: supportRoot, diagnostics: &diagnostics) {
                loadedSupportLibrary = true
            }
        }
        if !loadedSupportLibrary {
            for supportRoot in installedSupportLibraryRoots() {
                if preloadSupportLibraries(at: supportRoot, diagnostics: &diagnostics) {
                    loadedSupportLibrary = true
                }
            }
        }
        if !loadedSupportLibrary {
            diagnostics.append("no CoreCompiler support dylibs were loadable from installed assets or app Frameworks")
        }

        let coreCandidates = [
            embeddedFrameworkURL(named: "CoreCompiler"),
            toolchainRoot.appendingPathComponent("CoreCompiler.framework/CoreCompiler")
        ]
        for candidate in coreCandidates where fileExists(candidate) {
            if openDynamicLibrary(candidate, flags: RTLD_NOW | RTLD_GLOBAL, diagnostics: &diagnostics) != nil {
                return
            }
        }
        diagnostics.append("CoreCompiler.framework/CoreCompiler was not loadable from installed assets or app Frameworks")
    }

    private static func nativeDriverCandidates() -> [URL] {
        let embedded = embeddedFrameworkURL(named: "LitterBuildKitNative")
        let installed = nativeDriverURL
        return [embedded, installed]
    }

    private static func loadNativeDriver() -> NativeDriverLoadResult {
        var diagnostics: [String] = []
        let symbolName = "litter_buildkit_run_json"
        if let processHandle = processSymbolHandle, dlsym(processHandle, symbolName) != nil {
            diagnostics.append("found \(symbolName) in process symbol table")
            return NativeDriverLoadResult(handle: processHandle, diagnostics: diagnostics)
        }

        if installedManifest?.toolchain.nativeDriverMode == "inprocess" {
            preloadNativeDriverDependencies(diagnostics: &diagnostics)
        }

        for candidate in nativeDriverCandidates() {
            guard fileExists(candidate) else {
                diagnostics.append("missing native driver candidate \(candidate.path)")
                continue
            }
            guard let handle = openDynamicLibrary(candidate, flags: RTLD_NOW | RTLD_GLOBAL, diagnostics: &diagnostics) else {
                continue
            }
            if dlsym(handle, symbolName) != nil {
                diagnostics.append("found \(symbolName) in \(candidate.path)")
                return NativeDriverLoadResult(handle: handle, diagnostics: diagnostics)
            }
            diagnostics.append("missing \(symbolName) in \(candidate.path)")
        }
        return NativeDriverLoadResult(handle: nil, diagnostics: diagnostics)
    }

    private static func runNativeDriver(command: String, args: String, cwd: String, buildDir: String, staging: BuildKitHostStaging) -> BuildKitCommandResult? {
        let driver = loadNativeDriver()
        guard let handle = driver.handle, let symbol = dlsym(handle, "litter_buildkit_run_json") else { return nil }
        typealias RunFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
        let run = unsafeBitCast(symbol, to: RunFn.self)
        let nativeBuildDir = staging.hostWorkDir ?? buildDir
        let payload = NativeDriverRequest(
            command: command,
            args: args,
            cwd: cwd,
            buildDir: nativeBuildDir,
            buildKitRoot: buildKitRoot.path,
            toolchainRoot: toolchainRoot.path,
            sdkRoot: sdkRoot.path,
            clangResourceDir: clangResourceRoot.path,
            swiftResourceDir: swiftResourceRoot.path,
            cxxStandardLibraryIncludeDir: cxxStandardLibraryIncludeRoot.path,
            sdkVersion: installedManifest?.sdkVersion,
            swiftCompatibilityVersion: installedManifest?.swiftCompatibilityVersion,
            hostWorkDir: staging.hostWorkDir,
            hostProjectPath: staging.hostProjectPath,
            hostInputPath: staging.hostInputPath,
            fakefsProjectPath: staging.fakefsProjectPath,
            fakefsBuildDir: buildDir
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
        return BuildKitCommandResult(exitCode: response.exitCode, status: response.status, log: response.log, artifacts: response.artifacts ?? [])
    }

    private static func firstInputToken(in tokens: [String], extensions: Set<String>) -> String? {
        var skipNext = false
        for token in tokens {
            if skipNext {
                skipNext = false
                continue
            }
            if ["-o", "-I", "-F", "-L", "-isysroot", "--sysroot", "-target", "-arch", "-x", "-include", "-isystem", "-iquote", "-idirafter", "-framework", "-resource-dir", "-Xlinker"].contains(token) {
                skipNext = true
                continue
            }
            if token.hasPrefix("-") { continue }
            let ext = URL(fileURLWithPath: token).pathExtension.lowercased()
            if extensions.contains(ext) { return token }
        }
        return nil
    }

    private static func resolveFakefsPath(_ token: String, cwd: String) -> String {
        if token.hasPrefix("/") { return normalizedFakefsPath(token) }
        return normalizedFakefsPath((cwd as NSString).appendingPathComponent(token))
    }

    private static func plutilInputToken(_ tokens: [String]) -> String? {
        var values: [String] = []
        var skipNext = false
        for token in tokens {
            if skipNext {
                skipNext = false
                continue
            }
            if token == "-o" || token == "-convert" {
                skipNext = true
                continue
            }
            if token.hasPrefix("-") { continue }
            values.append(token)
        }
        return values.last
    }

    private static func plutilOutputPath(_ tokens: [String], inputPath: String, cwd: String) -> String {
        guard let outputIndex = tokens.firstIndex(of: "-o"), outputIndex + 1 < tokens.count else { return inputPath }
        let token = tokens[outputIndex + 1]
        if token == "-" { return token }
        return resolveFakefsPath(token, cwd: cwd)
    }

    private static func passThroughCandidates(for command: String) -> [String] {
        let aliases: [String]
        switch command {
        case "llvm-ar": aliases = ["llvm-ar", "ar"]
        case "llvm-ranlib": aliases = ["llvm-ranlib", "ranlib"]
        case "llvm-nm": aliases = ["llvm-nm", "nm"]
        case "llvm-objdump": aliases = ["llvm-objdump", "objdump"]
        default: aliases = [command]
        }
        let roots = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        return aliases.flatMap { alias in roots.map { "\($0)/\(alias)" } }
    }

    private static func firstFakefsExecutablePath(_ command: String) async -> String? {
        for path in passThroughCandidates(for: command) {
            if await IshFS.run("[ -x \(IshFS.shellQuote(path)) ]").exitCode == 0 { return path }
        }
        return nil
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

    static func shellWords(_ raw: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        for character in raw {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if character == "\\" && quote != "'" {
                escaping = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
                continue
            }
            if character == " " || character == "\t" || character == "\n" {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }

        if escaping { current.append("\\") }
        if !current.isEmpty { words.append(current) }
        return words
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

    private static func compatibilityProjectArgs(tokens: [String]) -> String {
        if let explicit = tokens.first(where: { $0.hasSuffix(".json") }) {
            return explicit
        }
        for flag in ["-project", "-workspace"] {
            if let index = tokens.firstIndex(of: flag), index + 1 < tokens.count {
                let projectPath = tokens[index + 1]
                if let inferred = inferredManifestPath(fromXcodeContainer: projectPath) {
                    return inferred
                }
            }
        }
        if let projectPath = tokens.first(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }),
           let inferred = inferredManifestPath(fromXcodeContainer: projectPath) {
            return inferred
        }
        return "LitterBuild.json"
    }

    private static func inferredManifestPath(fromXcodeContainer path: String) -> String? {
        guard path.hasSuffix(".xcodeproj") || path.hasSuffix(".xcworkspace") else { return nil }
        let parent = (path as NSString).deletingLastPathComponent
        if parent.isEmpty || parent == "." { return "LitterBuild.json" }
        return (parent as NSString).appendingPathComponent("LitterBuild.json")
    }

    private static func xcrunToolInvocation(tokens: [String]) -> (tool: String, args: [String])? {
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if ["--sdk", "-sdk", "--toolchain", "-toolchain", "--log", "--kill-cache"].contains(token) {
                index += 2
                continue
            }
            if token.hasPrefix("--sdk=") || token.hasPrefix("-sdk=") || token.hasPrefix("--toolchain=") || token.hasPrefix("-toolchain=") {
                index += 1
                continue
            }
            if token == "--run" {
                index += 1
                continue
            }
            if token.hasPrefix("-") {
                index += 1
                continue
            }
            let tool = token
            guard Self.commandNames.contains(tool), tool != "xcrun" else { return nil }
            return (tool, Array(tokens.dropFirst(index + 1)))
        }
        return nil
    }

    private static func tokensRequestSimulator(_ tokens: [String]) -> Bool {
        tokens.contains { token in
            let lower = token.lowercased()
            return lower.contains("iphonesimulator") || lower.contains("ios simulator") || lower.contains("platform=ios simulator")
        }
    }

    private static func xcodebuildSDKList() -> String {
        let sdk = installedManifest?.sdkVersion ?? "installed"
        return """
        iOS SDKs:
          iOS \(sdk)  -sdk iphoneos

        Litter BuildKit runs on device only. Simulator SDKs are intentionally unavailable.
        """
    }

    private static func xcodebuildListLog(projectArgs: String) -> String {
        """
        Information about project "LitterBuild":
            Targets:
                LitterBuild

            Build Configurations:
                Debug
                Release

            Schemes:
                LitterBuild

        Manifest: \(projectArgs)
        """
    }

    private static func xcodebuildSettingsLog(projectArgs: String) -> String {
        """
        Build settings for action build and target LitterBuild:
            ACTION = build
            ARCHS = arm64
            EFFECTIVE_PLATFORM_NAME = -iphoneos
            PLATFORM_NAME = iphoneos
            SDKROOT = \(sdkRoot.path)
            SUPPORTED_PLATFORMS = iphoneos
            TOOLCHAIN_DIR = \(toolchainRoot.path)
            CLANG_RESOURCE_DIR = \(clangResourceRoot.path)
            CXX_STANDARD_LIBRARY_INCLUDE_DIR = \(cxxStandardLibraryIncludeRoot.path)
            LITTER_BUILD_MANIFEST = \(projectArgs)
        """
    }

    private static func compatibilityVersionLog(tool: String, status: LitterBuildKitStatus) -> String {
        var output = "\(tool) compatibility shim for Litter BuildKit\n"
        output += "Swift: \(status.assetManifest?.swiftVersion ?? "unknown")\n"
        output += "SDK: \(status.assetManifest?.sdkVersion ?? "missing")\n"
        output += "Swift compatibility: \(status.assetManifest?.swiftCompatibilityVersion ?? "unknown")\n"
        output += "SDK Swift: \(status.assetManifest?.sdkSwiftVersion ?? "unknown")\n"
        output += "iPhoneOS SDK installed: \(status.sdkInstalled ? "yes" : "no")\n"
        output += "Clang resource dir installed: \(status.clangResourceDirInstalled ? "yes" : "no")\n"
        output += "Swift resource dir installed: \(status.swiftResourceDirInstalled ? "yes" : "no")\n"
        output += "libc++ headers installed: \(status.cxxStandardLibraryHeadersInstalled ? "yes" : "no")\n"
        output += "Native driver loadable: \(status.nativeDriverLoadable ? "yes" : "no")\n"
        if !status.nativeDriverLoadable && !status.nativeDriverDiagnostics.isEmpty {
            output += "Native driver diagnostics:\n"
            output += status.nativeDriverDiagnostics.prefix(8).map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        output += "Canonical commands: litter-swift-selftest, litter-swift-check, litter-swift-build, litter-swift-test, litter-ipa-build, litter-clang, litter-ld\n"
        return output
    }

    private static func swiftCompatibilityUsage() -> String {
        """
        Litter swift compatibility shim
        Supported:
          swift --version
          swift path/to/File.swift
          swift build [LitterBuild.json]
          swift test [LitterBuild.json]
          swift run [LitterBuild.json]  # build-only; iSH cannot execute iOS Mach-O output

        Canonical bot commands:
          litter-swift-selftest
          litter-swift-check path/to/File.swift
          litter-swift-build LitterBuild.json
          litter-swift-test LitterBuild.json
        """
    }

    private static func swiftcCompatibilityUsage() -> String {
        """
        Litter swiftc compatibility shim
        Supported:
          swiftc --version
          swiftc path/to/File.swift -o output
          swiftc -typecheck path/to/File.swift

        Canonical bot commands:
          litter-swift-selftest
          litter-swift-check path/to/File.swift
          litter-swiftc path/to/File.swift -o output
        """
    }

    private static func clangCompatibilityUsage(tool: String) -> String {
        """
        Litter \(tool) compatibility shim
        Supported:
          \(tool) --version
          \(tool) -c path/to/File.c -o File.o
          \(tool) path/to/File.c -o output

        Backend: Nyxian MDKDriver with the installed iPhoneOS SDK and arm64 iOS target.
        """
    }

    private static func ldCompatibilityUsage(tool: String) -> String {
        """
        Litter \(tool) compatibility shim
        Supported:
          \(tool) --version
          \(tool) input.o -o output

        Backend: Nyxian linker path. For most builds prefer clang or swiftc as the linker driver.
        """
    }

    private static func xcrunCompatibilityUsage() -> String {
        """
        Litter xcrun compatibility shim
        Supported:
          xcrun --sdk iphoneos --show-sdk-path
          xcrun --find swiftc
          xcrun --find clang
          xcrun --sdk iphoneos swiftc path/to/File.swift -o output
          xcrun --sdk iphoneos clang -c path/to/File.c -o File.o
          xcrun --version
        """
    }

    private static func plutilCompatibilityUsage() -> String {
        """
        Litter plutil compatibility shim
        Supported:
          plutil -lint Info.plist
          plutil -convert xml1 [-o output] Info.plist
          plutil -convert json [-o output] Info.plist
        """
    }

    private static func xcodebuildCompatibilityUsage() -> String {
        """
        Litter xcodebuild compatibility shim
        Supported:
          xcodebuild -version
          xcodebuild -showsdks
          xcodebuild -list
          xcodebuild -showBuildSettings
          xcodebuild [build] [LitterBuild.json]
          xcodebuild -project App.xcodeproj build
          xcodebuild test [LitterBuild.json]
          xcodebuild archive [LitterBuild.json]
          xcodebuild clean

        This is an iOS-device BuildKit bridge. It supports common Xcode-style discovery and routes builds through LitterBuild.json; simulator, Interface Builder, SwiftPM package resolution, and desktop signing workflows are intentionally unavailable on device.
        """
    }

    private static func statusLog(_ status: LitterBuildKitStatus) -> String {
        var output = """
        Litter BuildKit status
        Source import: \(status.sourceImportAvailable ? "present" : "missing")
        LiveContainer/ZSign source: \(status.liveContainerSourceAvailable ? "included" : "missing")
        LiveContainer OpenSSL framework: \(status.openSSLFrameworkVendored ? "included" : "missing")
        Private assets: \(status.privateAssetsInstalled ? "installed" : "missing")
        CoreCompiler assets: \(status.nativeCompilerAssetsInstalled ? "installed" : "missing")
        Native driver: \(status.nativeDriverInstalled ? "installed" : "missing")
        Native driver loadable: \(status.nativeDriverLoadable ? "yes" : "no")
        Native runner: \(status.nativeRunnerInstalled ? "installed" : "missing")
        Swift support libraries: \(status.supportLibrariesInstalled ? "installed" : "missing")
        iPhoneOS SDK: \(status.sdkInstalled ? "installed" : "missing")
        Clang resource dir: \(status.clangResourceDirInstalled ? "installed" : "missing")
        Swift resource dir: \(status.swiftResourceDirInstalled ? "installed" : "missing")
        libc++ headers: \(status.cxxStandardLibraryHeadersInstalled ? "installed" : "missing")
        Fakefs command shims: \(status.commandShimsInstalled ? "installed" : "missing")
        Request monitor: \(status.requestMonitorRunning ? "running" : "stopped")
        BuildKit root: \(status.buildKitRoot)
        Toolchain root: \(status.toolchainRoot)
        SDK root: \(status.sdkRoot)
        Clang resource root: \(clangResourceRoot.path)
        Swift resource root: \(swiftResourceRoot.path)
        libc++ include root: \(cxxStandardLibraryIncludeRoot.path)
        Swift direct build: \(status.canRunSwiftDirectly ? "ready" : "blocked")
        Unsigned IPA build: \(status.canBuildUnsignedIPA ? "ready" : "blocked")
        Commands: \(status.commands.joined(separator: ", "))
        Command modes: native Swift/Clang/link: swift, swiftc, clang, clang++, cc, c++, ld, ld64; compatibility: xcodebuild, xcode-select, xcrun, plutil, code; fakefs pass-through: ar, ranlib, nm, objdump, strip, strings, lipo.
        """
        if let sourceManifest = status.sourceImportManifest {
            output += "\nSource manifest: \(sourceManifest.name) (\(sourceManifest.importedFileCount) files)\n"
            if let capabilities = sourceManifest.includedCapabilities, !capabilities.isEmpty {
                output += "Source capabilities: \(capabilities.joined(separator: ", "))\n"
            }
            if let gaps = sourceManifest.knownSourceGaps, !gaps.isEmpty {
                output += "Source gaps: \(gaps.joined(separator: "; "))\n"
            }
        }
        if let manifest = status.assetManifest {
            output += "\nManifest: \(manifest.bundleIdentifier) SDK \(manifest.sdkVersion) Swift \(manifest.swiftVersion ?? "unknown")\n"
            output += "Native mode: \(manifest.toolchain.nativeDriverMode ?? "runner")\n"
            output += "Swift compatibility: \(manifest.swiftCompatibilityVersion ?? "unknown")\n"
            output += "SDK Swift: \(manifest.sdkSwiftVersion ?? "unknown")\n"
            output += "Clang resource dir: \(manifest.toolchain.clangResourceDir ?? "missing")\n"
            output += "Swift resource dir: \(manifest.toolchain.swiftResourceDir ?? "missing")\n"
            output += "libc++ include dir: \(manifest.toolchain.cxxStandardLibraryIncludeDir ?? "missing")\n"
            output += "Capabilities: \(manifest.capabilities.joined(separator: ", "))\n"
        }
        if !status.nativeDriverLoadable && !status.nativeDriverDiagnostics.isEmpty {
            output += "\nNative driver diagnostics:\n"
            output += status.nativeDriverDiagnostics.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !status.missingRequirements.isEmpty {
            output += "\nMissing requirements:\n" + status.missingRequirements.map { "- \($0)" }.joined(separator: "\n") + "\n"
            output += "\nAsset search:\n\(assetAvailabilityReport())\n"
        }
        return output
    }

    private static func nyxianStatusLog(_ status: LitterBuildKitStatus) -> String {
        var output = statusLog(status)
        output += "\nNyxian integration scan\n"
        output += "- Source import bundle marker: \(status.sourceImportAvailable ? "present" : "missing")\n"
        output += "- LiveContainer/ZSign source: \(status.liveContainerSourceAvailable ? "included" : "missing")\n"
        output += "- OpenSSL.xcframework: \(status.openSSLFrameworkVendored ? "included" : "missing")\n"
        output += "- Private asset root: \(status.buildKitRoot)\n"
        output += "- Swift direct execution: \(status.canRunSwiftDirectly ? "available" : "not available")\n"
        output += "- Unsigned IPA packaging: \(status.canBuildUnsignedIPA ? "available" : "not available")\n"
        output += "- Driver mode: \(status.assetManifest?.toolchain.nativeDriverMode ?? "unknown")\n"
        output += "- Capabilities: \(status.installedCapabilities.isEmpty ? "none" : status.installedCapabilities.joined(separator: ", "))\n"
        output += "\nBot path examples:\n"
        output += "- litter-swift-selftest\n"
        output += "- litter-swift-check /root/projects/App/Sources/App.swift\n"
        output += "- litter-swift-build /root/projects/App/LitterBuild.json\n"
        output += "- litter-ipa-build /root/projects/App/LitterBuild.json\n"
        return output
    }

    private static func missingAssetSummary(_ status: LitterBuildKitStatus) -> String {
        let missing = status.missingRequirements
        if missing.isEmpty { return "- BuildKit assets look present, but native execution failed.\n" }
        var output = missing.map { "- Missing \($0)." }.joined(separator: "\n") + "\n"
        if !status.nativeDriverDiagnostics.isEmpty {
            output += "\nNative driver diagnostics:\n"
            output += status.nativeDriverDiagnostics.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !status.privateAssetsInstalled {
            output += "\nAsset search:\n\(assetAvailabilityReport())\n"
        }
        return output
    }

    private static func commandShimScript() -> String {
        """
        #!/bin/sh
        set -eu
        root=${LITTER_BUILDKIT_ROOT:-/root/.litter/buildkit}
        requests="$root/requests"
        builds=${LITTER_BUILDKIT_BUILDS:-/root/.litter/builds}
        mkdir -p "$requests" "$builds"
        cmd="${0##*/}"
        quote_arg() {
          printf "'"
          printf '%s' "$1" | sed "s/'/'\\''/g"
          printf "'"
        }
        write_args() {
          first=1
          printf 'args='
          for arg in "$@"; do
            if [ "$first" -eq 0 ]; then printf ' '; fi
            quote_arg "$arg"
            first=0
          done
          printf '\\n'
        }
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
          write_args "$@"
        } > "$req"
        if [ "$wait_for_result" -eq 0 ]; then
          echo "Queued Litter BuildKit request: $id"
          echo "Status: litter-build-status $id"
          echo "Log: $builds/$id/log.txt"
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
    var clangResourceDir: String
    var swiftResourceDir: String
    var cxxStandardLibraryIncludeDir: String
    var sdkVersion: String?
    var swiftCompatibilityVersion: String?
    var hostWorkDir: String?
    var hostProjectPath: String?
    var hostInputPath: String?
    var fakefsProjectPath: String?
    var fakefsBuildDir: String?
}

private struct NativeDriverArtifact: Decodable, Sendable {
    var hostPath: String
    var fakefsPath: String?
}

private struct NativeDriverResponse: Decodable, Sendable {
    var exitCode: Int
    var status: String
    var log: String
    var artifacts: [NativeDriverArtifact]?
}

private struct BuildKitCommandResult: Sendable {
    var exitCode: Int
    var status: String
    var log: String
    var artifacts: [NativeDriverArtifact] = []

    var statusText: String {
        "exitCode=\(exitCode)\nstatus=\(status)\nupdatedAt=\(ISO8601DateFormatter().string(from: Date()))\n"
    }

    var logText: String { log }
}
