import Foundation

struct KittyStoreInstalledDeviceApp: Identifiable, Equatable, Sendable {
    var bundleIdentifier: String
    var name: String
    var shortVersion: String
    var version: String
    var applicationType: String
    var path: String
    var container: String

    var id: String { bundleIdentifier }

    var displayName: String {
        name.isEmpty ? bundleIdentifier : name
    }

    var displayVersion: String {
        if !shortVersion.isEmpty { return shortVersion }
        if !version.isEmpty { return version }
        return "Installed"
    }
}

struct KittyStoreInstalledAppsResult: Sendable {
    var exitCode: Int
    var status: String
    var log: String
    var apps: [KittyStoreInstalledDeviceApp]
}

enum KittyStoreMinimuxerBridge {
    enum Action: String, Sendable {
        case install
        case refresh
    }

    struct Result: Sendable {
        var exitCode: Int
        var status: String
        var log: String
    }

    struct LocalDevVPNProbe: Sendable {
        var isReady: Bool
        var endpointReachable: Bool
        var detail: String
    }

    static var isLinked: Bool {
        KittyStoreEmbeddedBridge.isMinimuxerTransportAvailable
    }

    static var isRuntimeReady: Bool {
        probeLocalDevVPN().isReady
    }

    static func probeLocalDevVPN() -> LocalDevVPNProbe {
        let probe = KittyStoreEmbeddedBridge.probeLocalDevVPN()
        return LocalDevVPNProbe(
            isReady: probe.isReady,
            endpointReachable: probe.endpointReachable,
            detail: probe.detail
        )
    }

    static func fetchUDID(pairingFileContents: String, consoleLoggingEnabled: Bool) async -> Result {
        await Task.detached(priority: .userInitiated) {
            do {
                let documentsPath = documentsLogPath()
                try KittyStoreEmbeddedBridge.startMinimuxer(
                    pairingFile: pairingFileContents,
                    logPath: documentsPath,
                    loggingEnabled: consoleLoggingEnabled
                )
                guard let udid = try KittyStoreEmbeddedBridge.fetchDeviceUDID(), !udid.isEmpty else {
                    return Result(exitCode: 69, status: "kittystore-udid-missing", log: "SideStore minimuxer did not return a device UDID.\n")
                }
                return Result(exitCode: 0, status: "kittystore-udid-ok", log: udid + "\n")
            } catch {
                return Result(exitCode: 70, status: "kittystore-udid-failed", log: Self.transportFailureLog(for: error))
            }
        }.value
    }

    static func listInstalledApps(
        pairingFileContents: String,
        consoleLoggingEnabled: Bool
    ) async -> KittyStoreInstalledAppsResult {
        await Task.detached(priority: .userInitiated) {
            do {
                var log: [String] = []
                let documentsPath = documentsLogPath()
                log.append("SideStore minimuxer installed-app browse")
                log.append("- Log path: \(documentsPath)")

                try KittyStoreEmbeddedBridge.startMinimuxer(
                    pairingFile: pairingFileContents,
                    logPath: documentsPath,
                    loggingEnabled: consoleLoggingEnabled
                )
                log.append("- SideStore minimuxer started with the imported pairing file")

                let plistText = try KittyStoreEmbeddedBridge.installedAppsPlist()
                let apps = try Self.parseInstalledApps(plistText: plistText)
                log.append("- loaded \(apps.count) user-installed app(s) through installation_proxy")

                let udid = try KittyStoreEmbeddedBridge.fetchDeviceUDID() ?? ""
                if !udid.isEmpty {
                    log.append("- device UDID: \(udid)")
                }
                return KittyStoreInstalledAppsResult(exitCode: 0, status: "kittystore-installed-ok", log: log.joined(separator: "\n") + "\n", apps: apps)
            } catch {
                return KittyStoreInstalledAppsResult(exitCode: 70, status: "kittystore-installed-failed", log: Self.transportFailureLog(for: error), apps: [])
            }
        }.value
    }

    static func installOrRefresh(
        action: Action,
        bundleIdentifier: String,
        pairingFileContents: String,
        ipaURL: URL?,
        provisioningProfileData: Data?,
        consoleLoggingEnabled: Bool
    ) async -> Result {
        await Task.detached(priority: .userInitiated) {
            do {
                var log: [String] = []
                let documentsPath = documentsLogPath()

                log.append("SideStore minimuxer transport")
                log.append("- Action: \(action.rawValue)")
                log.append("- Bundle ID: \(bundleIdentifier)")
                log.append("- Log path: \(documentsPath)")

                try KittyStoreEmbeddedBridge.startMinimuxer(
                    pairingFile: pairingFileContents,
                    logPath: documentsPath,
                    loggingEnabled: consoleLoggingEnabled
                )
                log.append("- SideStore minimuxer started with the imported pairing file")

                if let provisioningProfileData {
                    try KittyStoreEmbeddedBridge.installProvisioningProfile(provisioningProfileData)
                    log.append("- provisioning profile installed through misagent")
                }

                guard let ipaURL else {
                    log.append("- no IPA was provided; refresh requires a signed IPA payload")
                    return Result(exitCode: 64, status: "kittystore-refresh-missing-ipa", log: log.joined(separator: "\n") + "\n")
                }

                let ipaBytes = try Data(contentsOf: ipaURL, options: [.mappedIfSafe])
                log.append("- loaded signed IPA bytes: \(ipaBytes.count)")
                try KittyStoreEmbeddedBridge.stageIPA(bundleIdentifier: bundleIdentifier, ipaBytes: ipaBytes)
                log.append("- staged IPA into PublicStaging over AFC")
                try KittyStoreEmbeddedBridge.installStagedIPA(bundleIdentifier: bundleIdentifier)
                log.append("- install request sent through installation_proxy")

                let udid = try KittyStoreEmbeddedBridge.fetchDeviceUDID() ?? ""
                if !udid.isEmpty {
                    log.append("- device UDID: \(udid)")
                }
                let status = action == .install ? "kittystore-install-ok" : "kittystore-refresh-ok"
                return Result(exitCode: 0, status: status, log: log.joined(separator: "\n") + "\n")
            } catch {
                let status = action == .install ? "kittystore-install-failed" : "kittystore-refresh-failed"
                return Result(exitCode: 70, status: status, log: Self.transportFailureLog(for: error))
            }
        }.value
    }

    static func removeApp(
        bundleIdentifier: String,
        pairingFileContents: String,
        consoleLoggingEnabled: Bool
    ) async -> Result {
        await Task.detached(priority: .userInitiated) {
            do {
                var log: [String] = []
                let documentsPath = documentsLogPath()

                log.append("SideStore minimuxer remove")
                log.append("- Bundle ID: \(bundleIdentifier)")
                log.append("- Log path: \(documentsPath)")

                try KittyStoreEmbeddedBridge.startMinimuxer(
                    pairingFile: pairingFileContents,
                    logPath: documentsPath,
                    loggingEnabled: consoleLoggingEnabled
                )
                log.append("- SideStore minimuxer started with the imported pairing file")

                try KittyStoreEmbeddedBridge.removeInstalledApp(bundleIdentifier: bundleIdentifier)
                log.append("- uninstall request sent through installation_proxy")

                let udid = try KittyStoreEmbeddedBridge.fetchDeviceUDID() ?? ""
                if !udid.isEmpty {
                    log.append("- device UDID: \(udid)")
                }
                return Result(exitCode: 0, status: "kittystore-remove-ok", log: log.joined(separator: "\n") + "\n")
            } catch {
                return Result(exitCode: 70, status: "kittystore-remove-failed", log: Self.transportFailureLog(for: error))
            }
        }.value
    }

    private static func documentsLogPath() -> String {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documentsURL.path
    }

    private static func transportFailureLog(for error: Error) -> String {
        let rawDescription = "\(error.localizedDescription)\n\(String(describing: error))"
        let details = rawDescription.lowercased()
        if details.contains("connection reset")
            || details.contains("code: 54")
            || details.contains("broken pipe")
            || details.contains("network is down")
            || details.contains("not connected")
            || (details.contains("socket") && details.contains("reset"))
        {
            return "Unable to connect to the device. Make sure LocalDevVPN is enabled, this iPhone is on Wi-Fi, and the imported pairing file still matches this device.\n\(String(describing: error))\n"
        }
        return rawDescription + "\n"
    }

    private static func parseInstalledApps(plistText: String) throws -> [KittyStoreInstalledDeviceApp] {
        let data = Data(plistText.utf8)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return installedAppDictionaries(from: object)
            .compactMap { dictionary -> KittyStoreInstalledDeviceApp? in
                let bundleID = stringValue(dictionary["CFBundleIdentifier"])
                guard !bundleID.isEmpty else { return nil }
                let name = [
                    stringValue(dictionary["CFBundleDisplayName"]),
                    stringValue(dictionary["CFBundleName"]),
                    stringValue(dictionary["CFBundleExecutable"])
                ].first { !$0.isEmpty } ?? bundleID
                return KittyStoreInstalledDeviceApp(
                    bundleIdentifier: bundleID,
                    name: name,
                    shortVersion: stringValue(dictionary["CFBundleShortVersionString"]),
                    version: stringValue(dictionary["CFBundleVersion"]),
                    applicationType: stringValue(dictionary["ApplicationType"]),
                    path: stringValue(dictionary["Path"]),
                    container: stringValue(dictionary["Container"])
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private static func installedAppDictionaries(from object: Any) -> [[String: Any]] {
        if let array = object as? [[String: Any]] {
            return array
        }
        if let dictionary = object as? [String: Any] {
            if dictionary["CFBundleIdentifier"] != nil {
                return [dictionary]
            }
            return dictionary.values.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private static func stringValue(_ value: Any?) -> String {
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return ""
    }
}
