import Foundation

#if KITTYSTORE_MINIMUXER_LINKED
import Darwin
#endif

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

    static var isLinked: Bool {
        #if KITTYSTORE_MINIMUXER_LINKED
        true
        #else
        false
        #endif
    }

    static var isRuntimeReady: Bool {
        #if KITTYSTORE_MINIMUXER_LINKED
        #if targetEnvironment(simulator)
        return true
        #else
        return Minimuxer.ready()
        #endif
        #else
        return false
        #endif
    }

    static func fetchUDID(pairingFileContents: String, consoleLoggingEnabled: Bool) async -> Result {
        #if KITTYSTORE_MINIMUXER_LINKED
        return await Task.detached(priority: .userInitiated) {
            do {
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                setenv("USBMUXD_SOCKET_ADDRESS", "127.0.0.1:27015", 1)
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

                setenv("USBMUXD_SOCKET_ADDRESS", "127.0.0.1:27015", 1)
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

                setenv("USBMUXD_SOCKET_ADDRESS", "127.0.0.1:27015", 1)
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

}
