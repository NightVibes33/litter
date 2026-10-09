import Foundation

@MainActor
@objc(NyxianCommandBridge)
public final class NyxianCommandBridge: NSObject {
    // Keep the bridge source-compatible with the older pinned Nyxian headers
    // while the submodule is advanced. Upstream assigns raw value 5 to the
    // Ksurface kernel-extension project type.
    private static let kSurfaceKextKind = NXProjectSchemeKind(rawValue: 5)

    @objc(runJSON:completion:)
    public static func runJSON(_ requestJSON: String, completion: @escaping (String) -> Void) {
        Task { @MainActor in
            completion(await execute(requestJSON))
        }
    }

    private static func execute(_ requestJSON: String) async -> String {
        guard let data = requestJSON.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = request["command"] as? String else {
            return response(code: 64, status: "invalid-request", message: "Expected a JSON command request.")
        }

        if command == "bootstrap" {
            return await bootstrapEnvironment()
        }

        let bootstrapResponse = await bootstrapEnvironment()
        guard let bootstrapData = bootstrapResponse.data(using: .utf8),
              let bootstrapResult = try? JSONSerialization.jsonObject(with: bootstrapData) as? [String: Any],
              bootstrapResult["exitCode"] as? Int == 0 else {
            return bootstrapResponse
        }
        let root = NXBootstrap.shared().projectsURL

        switch command {
        case "projects":
            guard let groups = NXProject.listProjects(at: root) as? [String: [NXProject]] else {
                return response(code: 70, status: "projects-failed", message: "Nyxian could not read its project index.")
            }
            let projects: [[String: Any]] = groups.values.flatMap { $0 }.map {
                ["name": $0.projectConfig.displayName ?? $0.url.lastPathComponent,
                 "bundleIdentifier": $0.projectConfig.bundleid ?? "",
                 "type": schemeName($0.projectConfig.schemeKind),
                 "path": $0.url.path]
            }
            return response(code: 0, status: "projects", payload: ["projects": projects])

        case "create":
            guard let name = request["name"] as? String, !name.isEmpty else {
                return response(code: 64, status: "missing-name", message: "create requires name.")
            }
            let organization = request["organization"] as? String ?? "com.alleycat"
            let bundleID = request["bundleIdentifier"] as? String ?? "\(organization).\(slug(name))"
            let scheme = (request["type"] as? String)?.lowercased() ?? "app"
            // Nyxian's current Ksurface template is C. Litter's shell shim used
            // to always send Swift as its default, so normalize that legacy
            // default for KEXT/tweak requests unless a non-Swift language was
            // explicitly supplied.
            var language = (request["language"] as? String)?.lowercased() ?? "swift"
            if isKSurfaceAlias(scheme), language == "swift" {
                language = "c"
            }
            let interface = (request["interface"] as? String)?.lowercased() ?? "swiftui"
            guard let schemeKind = schemeKind(scheme),
                  let languageKind = languageKind(language),
                  let interfaceKind = interfaceKind(interface, scheme: schemeKind),
                  NXProjectConfigurationIsValid(schemeKind, interfaceKind, languageKind) else {
                return response(
                    code: 64,
                    status: "invalid-template",
                    message: "Unsupported Nyxian project template combination. Apps support Swift/Objective-C UI projects; Ksurface extensions use the upstream KEXT template."
                )
            }
            guard let project = NXProject.createProject(
                at: root,
                withName: name,
                withOrganizationIdentifier: organization,
                withBundleIdentifier: bundleID,
                withSchemeKind: schemeKind,
                withLanguageKind: languageKind,
                withInterfaceKind: interfaceKind
            ) else {
                return response(code: 70, status: "create-failed", message: "Nyxian could not create the project.")
            }
            return response(
                code: 0,
                status: "created",
                payload: [
                    "path": project.url.path,
                    "bundleIdentifier": bundleID,
                    "type": schemeName(schemeKind),
                    "language": language
                ]
            )

        case "info", "diagnostics", "clean":
            guard let path = request["path"] as? String, !path.isEmpty,
                  let project = NXProject(url: URL(fileURLWithPath: path)) else {
                return response(code: 66, status: "project-not-found", message: "Expected a valid Nyxian project path.")
            }
            let diagnosticsURL = project.cacheURL.appendingPathComponent("debug.json")
            if command == "info" {
                return response(code: 0, status: "project-info", payload: [
                    "projectPath": project.url.path,
                    "name": project.projectConfig.displayName ?? "",
                    "bundleIdentifier": project.projectConfig.bundleid ?? "",
                    "type": schemeName(project.projectConfig.schemeKind),
                    "deploymentTarget": project.projectConfig.deploymentTarget ?? "",
                    "swiftFlags": project.projectConfig.swiftFlags ?? [],
                    "compilerFlags": project.projectConfig.compilerFlags ?? [],
                    "linkerFlags": project.projectConfig.linkerFlags ?? [],
                    "artifactPath": project.packageURL.path,
                    "diagnosticsPath": diagnosticsURL.path
                ])
            }
            guard !NXBuilder.builds else {
                return response(code: 75, status: "build-busy", message: "Wait for the active Nyxian build to finish before reading its diagnostics or cleaning.")
            }
            if command == "diagnostics" {
                do {
                    return response(code: 0, status: "diagnostics", payload: [
                        "projectPath": project.url.path,
                        "diagnosticsPath": diagnosticsURL.path,
                        "diagnostics": try readDiagnostics(at: diagnosticsURL)
                    ])
                } catch {
                    return response(code: 74, status: "diagnostics-unavailable", message: error.localizedDescription,
                                    payload: ["diagnosticsPath": diagnosticsURL.path])
                }
            }
            guard let builder = NXBuilder(project: project) else {
                return response(code: 70, status: "builder-unavailable", message: "Upstream Nyxian could not initialize this project's builder.")
            }
            NXBuilder.builds = true
            defer { NXBuilder.builds = false }
            do {
                try builder.clean()
                return response(code: 0, status: "clean-complete", message: "Upstream Nyxian cleanup completed; this is not a build or test result.",
                                payload: ["projectPath": project.url.path])
            } catch {
                return response(code: 74, status: "clean-failed", message: error.localizedDescription)
            }

        case "build", "run":
            guard let path = request["path"] as? String, !path.isEmpty else {
                return response(code: 64, status: "missing-path", message: "\(command) requires path.")
            }
            guard let project = NXProject(url: URL(fileURLWithPath: path)) else {
                return response(code: 66, status: "project-not-found", message: "Nyxian could not open the project at the requested path.")
            }
            let projectKind = project.projectConfig.schemeKind

            // Upstream's Ksurface .run path installs the KEXT and restarts the
            // host process. Codex should be able to create/edit/export these
            // projects without unexpectedly killing Alley Cat. Installation is
            // deliberately kept as an explicit user action in the Nyxian UI.
            if command == "run", projectKind.rawValue == kSurfaceKextKind.rawValue {
                return response(
                    code: 64,
                    status: "kext-run-requires-ui",
                    message: "Ksurface extension export is supported through nyxian build. Loading it is an explicit EmexDE/Nyxian UI action because upstream restarts the host after installation.",
                    payload: ["projectPath": project.url.path, "type": schemeName(projectKind)]
                )
            }

            guard !NXBuilder.builds else {
                return response(code: 75, status: "build-busy", message: "An EmexDE build is already running.")
            }
            NXBuilder.builds = true
            defer { NXBuilder.builds = false }
            // Suspend the command while upstream builds on its worker queue.
            // Blocking the main thread here freezes the IDE and signing UI.
            let (success, executablePath): (Bool, String?) = await withCheckedContinuation { continuation in
                NXBuilder.buildProject(withProject: project, buildType: command == "run" ? .run : .export) { result, output in
                    continuation.resume(returning: (result, output))
                }
            }
            let artifact = command == "build" ? project.packageURL.path : (executablePath ?? "")
            return response(
                code: success ? 0 : 65,
                status: success ? "\(command)-complete" : "\(command)-failed",
                payload: [
                    "projectPath": project.url.path,
                    "artifactPath": artifact,
                    "type": schemeName(projectKind),
                    "diagnosticsPath": project.cacheURL.appendingPathComponent("debug.json").path,
                    "diagnostics": (try? readDiagnostics(at: project.cacheURL.appendingPathComponent("debug.json"))) ?? NSNull()
                ]
            )

        default:
            return response(code: 64, status: "unsupported-command", message: "Supported commands: projects, create, info, diagnostics, clean, build, run.")
        }
    }

    private static func readDiagnostics(at url: URL) throws -> Any {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 4_000_000 else {
            throw NSError(domain: "NyxianCommandBridge", code: 74,
                          userInfo: [NSLocalizedDescriptionKey: "Diagnostics must be a regular JSON file no larger than 4 MB. Read the reported path for larger logs."])
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 4_000_001) ?? Data()
        guard data.count <= 4_000_000, data.count == size.intValue else {
            throw NSError(domain: "NyxianCommandBridge", code: 74,
                          userInfo: [NSLocalizedDescriptionKey: "Diagnostics grew beyond the response limit."])
        }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static var bootstrapTask: Task<String, Never>?

    private static func bootstrapEnvironment() async -> String {
        if let task = bootstrapTask { return await task.value }
        let task = Task { @MainActor in
            let bootstrap = NXBootstrap.shared()
            if !bootstrap.isNewest() {
                bootstrap.bootstrap()
                // Upstream bootstrap performs extraction/download on its worker.
                // Poll asynchronously so the app and progress UI remain responsive.
                for _ in 0..<900 {
                    if bootstrap.isNewest() { break }
                    do { try await Task.sleep(for: .seconds(1)) }
                    catch { return response(code: 130, status: "bootstrap-cancelled", message: "Nyxian bootstrap wait was cancelled.") }
                }
            }
            guard bootstrap.isNewest() else {
                return response(code: 78, status: "bootstrap-incomplete", message: "Nyxian bootstrap did not finish. Check its download/progress error and retry.")
            }
            let required = [
                bootstrap.sdkURL.appendingPathComponent("SDKSettings.plist"),
                bootstrap.includeURL.appendingPathComponent("include/stdarg.h"),
                bootstrap.swiftURL.appendingPathComponent("iphoneos", isDirectory: true)
            ]
            guard required.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
                return response(code: 78, status: "bootstrap-resources-missing", message: "Nyxian reports a current bootstrap, but required SDK/compiler resources are missing.")
            }
            let paths = [
                "sdkRoot": bootstrap.sdkURL.path,
                "clangResourceRoot": bootstrap.includeURL.path,
                "swiftResourceRoot": bootstrap.swiftURL.path,
                "cxxStandardLibraryIncludeRoot": bootstrap.sdkURL.appendingPathComponent("usr/include/c++/v1").path
            ]
            do {
                let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/BuildKit", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: paths).write(to: root.appendingPathComponent("nyxian-runtime.json"), options: .atomic)
            } catch {
                return response(code: 74, status: "bootstrap-paths-failed", message: error.localizedDescription)
            }
            return response(code: 0, status: "bootstrap-ready", payload: paths)
        }
        bootstrapTask = task
        let result = await task.value
        bootstrapTask = nil
        return result
    }

    private static func schemeKind(_ value: String) -> NXProjectSchemeKind? {
        switch value {
        case "app", "application": return .app
        case "utility", "tool", "cli": return .utility
        case "kext", "ksurface-kext", "ksurface", "tweak": return kSurfaceKextKind
        default: return nil
        }
    }

    private static func schemeName(_ kind: NXProjectSchemeKind) -> String {
        if kind == .app { return "app" }
        if kind == .utility { return "utility" }
        if kind.rawValue == kSurfaceKextKind.rawValue { return "ksurface-kext" }
        return "unknown"
    }

    private static func isKSurfaceAlias(_ value: String) -> Bool {
        ["kext", "ksurface-kext", "ksurface", "tweak"].contains(value)
    }

    private static func languageKind(_ value: String) -> NXProjectLanguageKind? {
        switch value {
        case "swift": return .swift
        case "objc", "objective-c": return .objectiveC
        case "c": return .C
        case "cpp", "c++": return .CXX
        default: return nil
        }
    }

    private static func interfaceKind(_ value: String, scheme: NXProjectSchemeKind) -> NXProjectInterfaceKind? {
        guard scheme == .app else { return .unknown }
        switch value {
        case "swiftui": return .swiftUI
        case "uikit": return .uiKit
        default: return nil
        }
    }

    private static func slug(_ value: String) -> String {
        value.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
    }

    private static func response(code: Int, status: String, message: String? = nil, payload: [String: Any] = [:]) -> String {
        var body = payload
        body["exitCode"] = code
        body["status"] = status
        if let message { body["message"] = message }
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            return "{\"exitCode\":70,\"status\":\"encode-failed\"}"
        }
        return String(data: data, encoding: .utf8) ?? "{\"exitCode\":70,\"status\":\"encode-failed\"}"
    }
}
