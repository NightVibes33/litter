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

        NXBootstrap.shared().bootstrap()
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

        case "build", "run":
            guard let path = request["path"] as? String, !path.isEmpty else {
                return response(code: 64, status: "missing-path", message: "\(command) requires path.")
            }
            let project = NXProject(url: URL(fileURLWithPath: path))
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
                    "type": schemeName(projectKind)
                ]
            )

        default:
            return response(code: 64, status: "unsupported-command", message: "Supported commands: projects, create, build, run.")
        }
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
