import Foundation

#if KITTYSTORE_MINIMUXER_LINKED
import Darwin
#endif

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
        #if KITTYSTORE_MINIMUXER_LINKED
        true
        #else
        false
        #endif
    }

    static var isRuntimeReady: Bool {
        probeLocalDevVPN().isReady
    }

    static func probeLocalDevVPN() -> LocalDevVPNProbe {
        #if KITTYSTORE_MINIMUXER_LINKED
        #if targetEnvironment(simulator)
        return LocalDevVPNProbe(isReady: true, endpointReachable: true, detail: "Simulator build treats the SideStore minimuxer transport as ready.")
        #else
        configureSideStoreNetworkBridge()
        let ready = Minimuxer.ready()
        let endpointReachable = Minimuxer.testLocalDevVPNConnection()
        let detail: String
        if ready {
            detail = "SideStore minimuxer is ready through LocalDevVPN override IP 10.7.0.1."
        } else if endpointReachable {
            detail = "LocalDevVPN 10.7.0.1 is reachable. Pairing will be checked during install or refresh."
        } else {
            detail = "LocalDevVPN 10.7.0.1 is not reachable yet."
        }
        return LocalDevVPNProbe(isReady: ready, endpointReachable: endpointReachable, detail: detail)
        #endif
        #else
        return LocalDevVPNProbe(isReady: false, endpointReachable: false, detail: "SideStore minimuxer is not linked into this Litter build.")
        #endif
    }

    static func fetchUDID(pairingFileContents: String, consoleLoggingEnabled: Bool) async -> Result {
        #if KITTYSTORE_MINIMUXER_LINKED
        return await Task.detached(priority: .userInitiated) {
            do {
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                configureSideStoreNetworkBridge()
                try Minimuxer.startWithLogger(
                    pairingFile: pairingFileContents,
                    logPath: documentsURL.absoluteString,
                    isConsoleLoggingEnabled: consoleLoggingEnabled
                )
                guard let udid = Minimuxer.fetchUDID(), !udid.isEmpty else {
                    return Result(exitCode: 69, status: "sidestore-udid-missing", log: "minimuxer did not return a device UDID.\n")
                }
                return Result(exitCode: 0, status: "sidestore-udid-ok", log: udid + "\n")
            } catch {
                return Result(exitCode: 70, status: "sidestore-udid-failed", log: "\(error.localizedDescription)\n\(String(describing: error))\n")
            }
        }.value
        #else
        return Result(
            exitCode: 78,
            status: "sidestore-minimuxer-not-linked",
            log: "SideStore minimuxer is not linked into this Litter build.\n"
        )
        #endif
    }

    static func listInstalledApps(
        pairingFileContents: String,
        consoleLoggingEnabled: Bool
    ) async -> KittyStoreInstalledAppsResult {
        #if KITTYSTORE_MINIMUXER_LINKED
        return await Task.detached(priority: .userInitiated) {
            do {
                var log: [String] = []
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                let documentsPath = documentsURL.absoluteString

                configureSideStoreNetworkBridge()
                log.append("SideStore minimuxer installed-app browse")
                log.append("- Log path: \(documentsPath)")

                try Minimuxer.startWithLogger(
                    pairingFile: pairingFileContents,
                    logPath: documentsPath,
                    isConsoleLoggingEnabled: consoleLoggingEnabled
                )
                log.append("- minimuxer started with the imported pairing file")

                let plistText = try Minimuxer.listInstalledAppsPlist()
                let apps = try Self.parseInstalledApps(plistText: plistText)
                log.append("- loaded \(apps.count) user-installed app(s) through installation_proxy")

                let udid = Minimuxer.fetchUDID() ?? ""
                if !udid.isEmpty {
                    log.append("- device UDID: \(udid)")
                }
                return KittyStoreInstalledAppsResult(exitCode: 0, status: "kittystore-installed-ok", log: log.joined(separator: "\n") + "\n", apps: apps)
            } catch {
                return KittyStoreInstalledAppsResult(exitCode: 70, status: "kittystore-installed-failed", log: "\(error.localizedDescription)\n\(String(describing: error))\n", apps: [])
            }
        }.value
        #else
        return KittyStoreInstalledAppsResult(
            exitCode: 78,
            status: "sidestore-minimuxer-not-linked",
            log: "SideStore minimuxer is not linked into this Litter build.\n",
            apps: []
        )
        #endif
    }

    static func installOrRefresh(
        action: Action,
        bundleIdentifier: String,
        pairingFileContents: String,
        ipaURL: URL?,
        provisioningProfileData: Data?,
        consoleLoggingEnabled: Bool
    ) async -> Result {
        #if KITTYSTORE_MINIMUXER_LINKED
        return await Task.detached(priority: .userInitiated) {
            do {
                var log: [String] = []
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                let documentsPath = documentsURL.absoluteString

                configureSideStoreNetworkBridge()
                log.append("SideStore minimuxer transport")
                log.append("- Action: \(action.rawValue)")
                log.append("- Bundle ID: \(bundleIdentifier)")
                log.append("- Log path: \(documentsPath)")

                try Minimuxer.startWithLogger(
                    pairingFile: pairingFileContents,
                    logPath: documentsPath,
                    isConsoleLoggingEnabled: consoleLoggingEnabled
                )
                log.append("- minimuxer started with the imported pairing file")

                if let provisioningProfileData {
                    try Minimuxer.installProvisioningProfile(profile: provisioningProfileData)
                    log.append("- provisioning profile installed through misagent")
                }

                guard let ipaURL else {
                    log.append("- no IPA was provided; refresh requires a signed IPA payload")
                    return Result(exitCode: 64, status: "kittystore-refresh-missing-ipa", log: log.joined(separator: "\n") + "\n")
                }

                let ipaBytes = try Data(contentsOf: ipaURL, options: [.mappedIfSafe])
                log.append("- loaded signed IPA bytes: \(ipaBytes.count)")
                try Minimuxer.yeetAppAfc(bundleId: bundleIdentifier, ipaBytes: ipaBytes)
                log.append("- staged IPA into PublicStaging over AFC")
                try Minimuxer.installIpa(bundleId: bundleIdentifier)
                log.append("- install request sent through installation_proxy")

                let udid = Minimuxer.fetchUDID() ?? ""
                if !udid.isEmpty {
                    log.append("- device UDID: \(udid)")
                }
                let status = action == .install ? "kittystore-install-ok" : "kittystore-refresh-ok"
                return Result(exitCode: 0, status: status, log: log.joined(separator: "\n") + "\n")
            } catch {
                let status = action == .install ? "kittystore-install-failed" : "kittystore-refresh-failed"
                return Result(exitCode: 70, status: status, log: "\(error.localizedDescription)\n\(String(describing: error))\n")
            }
        }.value
        #else
        return Result(
            exitCode: 78,
            status: "sidestore-minimuxer-not-linked",
            log: """
            SideStore minimuxer is not linked into this Litter build.
            Rebuild the iOS app with tools/scripts/build-sidestore-minimuxer.sh and KITTYSTORE_MINIMUXER_LINKED enabled so the vendored SideStore minimuxer Rust bridge is compiled into the app process.
            """
        )
        #endif
    }
    static func removeApp(
        bundleIdentifier: String,
        pairingFileContents: String,
        consoleLoggingEnabled: Bool
    ) async -> Result {
        #if KITTYSTORE_MINIMUXER_LINKED
        return await Task.detached(priority: .userInitiated) {
            do {
                var log: [String] = []
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                let documentsPath = documentsURL.absoluteString

                configureSideStoreNetworkBridge()
                log.append("SideStore minimuxer remove")
                log.append("- Bundle ID: \(bundleIdentifier)")
                log.append("- Log path: \(documentsPath)")

                try Minimuxer.startWithLogger(
                    pairingFile: pairingFileContents,
                    logPath: documentsPath,
                    isConsoleLoggingEnabled: consoleLoggingEnabled
                )
                log.append("- minimuxer started with the imported pairing file")

                try Minimuxer.removeApp(bundleId: bundleIdentifier)
                log.append("- uninstall request sent through installation_proxy")

                let udid = Minimuxer.fetchUDID() ?? ""
                if !udid.isEmpty {
                    log.append("- device UDID: \(udid)")
                }
                return Result(exitCode: 0, status: "kittystore-remove-ok", log: log.joined(separator: "\n") + "\n")
            } catch {
                return Result(exitCode: 70, status: "kittystore-remove-failed", log: "\(error.localizedDescription)\n\(String(describing: error))\n")
            }
        }.value
        #else
        return Result(
            exitCode: 78,
            status: "sidestore-minimuxer-not-linked",
            log: """
            SideStore minimuxer is not linked into this Litter build.
            Rebuild the iOS app with tools/scripts/build-sidestore-minimuxer.sh and KITTYSTORE_MINIMUXER_LINKED enabled so the vendored SideStore minimuxer Rust bridge is compiled into the app process.
            """
        )
        #endif
    }

    #if KITTYSTORE_MINIMUXER_LINKED
    private static func configureSideStoreNetworkBridge() {
        #if !targetEnvironment(simulator)
        setenv("USBMUXD_SOCKET_ADDRESS", "127.0.0.1:27015", 1)
        Minimuxer.retargetUsbmuxdAddr()
        #endif
    }
    #endif

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
