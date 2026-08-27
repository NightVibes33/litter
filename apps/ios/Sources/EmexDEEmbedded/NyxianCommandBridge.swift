import Foundation

@MainActor
@objc(NyxianCommandBridge)
public final class NyxianCommandBridge: NSObject {
    @objc(runJSON:)
    public static func runJSON(_ requestJSON: String) -> String {
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
                 "path": $0.url.path]
            }
            return response(code: 0, status: "projects", payload: ["projects": projects])

        case "create":
            guard let name = request["name"] as? String, !name.isEmpty else {
                return response(code: 64, status: "missing-name", message: "create requires name.")
            }
            let organization = request["organization"] as? String ?? "com.alleycat"
            let bundleID = request["bundleIdentifier"] as? String ?? "\(organization).\(slug(name))"
            let language = (request["language"] as? String)?.lowercased() ?? "swift"
            let scheme = (request["type"] as? String)?.lowercased() ?? "app"
            let interface = (request["interface"] as? String)?.lowercased() ?? "swiftui"
            guard let schemeKind = schemeKind(scheme),
                  let languageKind = languageKind(language),
                  let interfaceKind = interfaceKind(interface, scheme: schemeKind),
                  NXProjectConfigurationIsValid(schemeKind, interfaceKind, languageKind) else {
                return response(code: 64, status: "invalid-template", message: "Unsupported Nyxian project template combination.")
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
            return response(code: 0, status: "created", payload: ["path": project.url.path, "bundleIdentifier": bundleID])

        case "build", "run":
            guard let path = request["path"] as? String, !path.isEmpty else {
                return response(code: 64, status: "missing-path", message: "\(command) requires path.")
            }
            let project = NXProject(url: URL(fileURLWithPath: path))
            let semaphore = DispatchSemaphore(value: 0)
            let buildResult = NyxianBuildResult()
            NXBuilder.buildProject(withProject: project, buildType: command == "run" ? .run : .export) { result, output in
                buildResult.success = result
                buildResult.executablePath = output
                semaphore.signal()
            }
            semaphore.wait()
            let artifact = command == "build" ? project.packageURL.path : (buildResult.executablePath ?? "")
            return response(code: buildResult.success ? 0 : 65, status: buildResult.success ? "\(command)-complete" : "\(command)-failed", payload: ["projectPath": project.url.path, "artifactPath": artifact])

        default:
            return response(code: 64, status: "unsupported-command", message: "Supported commands: projects, create, build, run.")
        }
    }

    private static func schemeKind(_ value: String) -> NXProjectSchemeKind? {
        switch value {
        case "app", "application": return .app
        case "utility", "tool", "cli": return .utility
        default: return nil
        }
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

private final class NyxianBuildResult: @unchecked Sendable {
    var success = false
    var executablePath: String?
}
