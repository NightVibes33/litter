//
//  MinimuxerWrapper.swift
//
//  Created by Magesh K on 22/02/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import Minimuxer

func bindTunnelConfig() {
    defer { print("[KittyStore] bindTunnelConfig() completed") }

    #if targetEnvironment(simulator)
    print("[KittyStore] bindTunnelConfig() is no-op on simulator")
    #else
    print("[KittyStore] bindTunnelConfig() invoked")

    Task { @MainActor in
        let config = TunnelConfig.shared
        Minimuxer.bindTunnelConfig(
            TunnelConfigBinding(
                setDeviceIP: { value in Task { @MainActor in config.deviceIP = value } },
                setFakeIP: { value in Task { @MainActor in config.fakeIP = value } },
                setSubnetMask: { value in Task { @MainActor in config.subnetMask = value } },
                getOverrideFakeIP: { config.overrideFakeIP },
                setOverrideEffective: { value in Task { @MainActor in config.overrideEffective = value } }
            )
        )
    }
    #endif
}


var isMinimuxerReady: Bool {
    var result = true
    #if targetEnvironment(simulator)
    print("[KittyStore] isMinimuxerReady = true on simulator")
    #else
    result = Minimuxer.ready()
    print("[KittyStore] isMinimuxerReady = \(result)")
    #endif
    return result
}


func retargetUsbmuxdAddr() {
    defer { print("[KittyStore] retargetUsbmuxdAddr() completed") }
    #if targetEnvironment(simulator)
    print("[KittyStore] retargetUsbmuxdAddr() is no-op on simulator")
    #else
    print("[KittyStore] retargetUsbmuxdAddr() invoked")
    Minimuxer.retargetUsbmuxdAddr()
    #endif
}

func minimuxerStartWithLogger(_ pairingFile: String, _ logPath: String, _ loggingEnabled: Bool) throws {
    defer { print("[KittyStore] minimuxerStartWithLogger(pairingFile, logPath, dest, loggingEnabled) completed") }
    #if targetEnvironment(simulator)
    print("[KittyStore] minimuxerStartWithLogger(pairingFile, logPath, loggingEnabled) is no-op on simulator")
    #else
    // refresh config if any
    bindTunnelConfig()
    // observe network route changes (and update device endpoint from vpn(utun))
    NetworkObserver.shared.start()
    
    print("[KittyStore] minimuxerStartWithLogger(pairingFile, logPath, dest, loggingEnabled) invoked")
    try Minimuxer.startWithLogger(pairingFile: pairingFile,
                                  logPath: logPath,
                                  isConsoleLoggingEnabled: loggingEnabled)
    #endif
}

func installProvisioningProfiles(_ profileData: Data) throws {
    defer { print("[KittyStore] installProvisioningProfiles(profileData) completed") }
    #if targetEnvironment(simulator)
    print("[KittyStore] installProvisioningProfiles(profileData) is no-op on simulator")
    #else
    print("[KittyStore] installProvisioningProfiles(profileData) invoked")
    do {
        try Minimuxer.installProvisioningProfile(profile: profileData)
    } catch {
        throw normalizedMinimuxerTransportError(error)
    }
    #endif
}

func removeProvisioningProfile(_ id: String) throws {
    defer { print("[KittyStore] removeProvisioningProfile(id) completed") }
    #if targetEnvironment(simulator)
    print("[KittyStore] removeProvisioningProfile(id) is no-op on simulator")
    #else
    print("[KittyStore] removeProvisioningProfile(id) invoked")
    do {
        try Minimuxer.removeProvisioningProfile(id: id)
    } catch {
        throw normalizedMinimuxerTransportError(error)
    }
    #endif
}

func removeApp(_ bundleId: String) throws {
    defer { print("[KittyStore] removeApp(bundleId) completed") }
    #if targetEnvironment(simulator)
    print("[KittyStore] removeApp(bundleId) is no-op on simulator")
    #else
    print("[KittyStore] removeApp(bundleId) invoked")
    do {
        try Minimuxer.removeApp(bundleId: bundleId)
    } catch {
        throw normalizedMinimuxerTransportError(error)
    }
    #endif
}

func yeetAppAFC(_ bundleId: String, _ rawBytes: Data) throws {
    defer { print("[KittyStore] yeetAppAFC(bundleId, rawBytes) completed") }
    #if targetEnvironment(simulator)
    print("[KittyStore] yeetAppAFC(bundleId, rawBytes) is no-op on simulator")
    #else
    print("[KittyStore] yeetAppAFC(bundleId, rawBytes) invoked")
    do {
        try Minimuxer.yeetAppAfc(bundleId: bundleId, ipaBytes: rawBytes)
    } catch {
        throw normalizedMinimuxerTransportError(error)
    }
    #endif
}

func installIPA(_ bundleId: String) throws {
    defer { print("[KittyStore] installIPA(bundleId) completed") }
    #if targetEnvironment(simulator)
    print("[KittyStore] installIPA(bundleId) is no-op on simulator")
    #else
    print("[KittyStore] installIPA(bundleId) invoked")
    try ensureMinimuxerInstallTransportReady()
    do {
        try Minimuxer.installIpa(bundleId: bundleId)
    } catch {
        throw normalizedMinimuxerTransportError(error)
    }
    #endif
}

private func ensureMinimuxerInstallTransportReady() throws {
    #if targetEnvironment(simulator)
    return
    #else
    guard isMinimuxerReady else {
        throw MinimuxerError.NoConnection
    }
    #endif
}

private func normalizedMinimuxerTransportError(_ error: Error) -> Error {
    if error is MinimuxerError { return error }

    let details = "\(error.localizedDescription)\n\(String(describing: error))".lowercased()
    if details.contains("connection reset")
        || details.contains("code: 54")
        || details.contains("broken pipe")
        || details.contains("network is down")
        || details.contains("not connected")
        || (details.contains("socket") && details.contains("reset"))
    {
        print("[KittyStore] normalized minimuxer transport error: \(error)")
        return MinimuxerError.NoConnection
    }

    return error
}

func fetchUDID() -> String? {
    defer { print("[KittyStore] fetchUDID() completed") }
    #if targetEnvironment(simulator)
    print("[KittyStore] fetchUDID() is no-op on simulator")
    return "XXXXX-XXXX-XXXXX-XXXX"
    #else
    print("[KittyStore] fetchUDID() invoked")
    if let udid = Minimuxer.fetchUDID()?.trimmingCharacters(in: .whitespacesAndNewlines), !udid.isEmpty {
        return udid
    }
    if let udid = storedPairingUDID() {
        print("[KittyStore] fetchUDID() using imported pairing fallback")
        return udid
    }
    return nil
    #endif
}

#if !targetEnvironment(simulator)
private func storedPairingUDID() -> String? {
    let fileManager = FileManager.default
    let documentsURL = fileManager.documentsDirectory.appendingPathComponent(pairingFileName)
    if let udid = pairingUDID(from: documentsURL) { return udid }

    if !UserDefaults.standard.isPairingReset,
       let bundledURL = Bundle.main.url(forResource: "ALTPairingFile", withExtension: "mobiledevicepairing"),
       let udid = pairingUDID(from: bundledURL) {
        return udid
    }

    if !UserDefaults.standard.isPairingReset,
       let plistString = Bundle.main.object(forInfoDictionaryKey: "ALTPairingFile") as? String,
       !plistString.isEmpty,
       !plistString.contains("insert pairing file here") {
        return pairingUDID(from: Data(plistString.utf8))
    }

    return nil
}

private func pairingUDID(from url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return pairingUDID(from: data)
}

private func pairingUDID(from data: Data, depth: Int = 0) -> String? {
    guard depth < 3,
          let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
          let dictionary = plist as? [String: Any] else {
        return nil
    }

    for key in ["UDID", "UniqueDeviceID", "SerialNumber", "Identifier", "identifier"] {
        if let udid = normalizedUDID(dictionary[key]) { return udid }
    }

    if let pairRecordData = dictionary["PairRecordData"] as? Data,
       let udid = pairingUDID(from: pairRecordData, depth: depth + 1) {
        return udid
    }

    return nil
}

private func normalizedUDID(_ value: Any?) -> String? {
    let string: String?
    if let raw = value as? String {
        string = raw
    } else if let number = value as? NSNumber {
        string = number.stringValue
    } else {
        string = nil
    }

    guard let udid = string?.trimmingCharacters(in: .whitespacesAndNewlines), !udid.isEmpty else {
        return nil
    }
    return udid
}
#endif

func debugApp(_ appId: String) throws {
    defer { print("[KittyStore] debugApp(appId) completed") }
    #if targetEnvironment(simulator)
    print("[KittyStore] debugApp(appId) is no-op on simulator")
    #else
    print("[KittyStore] debugApp(appId) invoked")
    try Minimuxer.debugApp(appId: appId)
    #endif
}

func attachDebugger(_ pid: UInt32) throws {
    defer { print("[KittyStore] attachDebugger(pid) completed") }
    #if targetEnvironment(simulator)
    print("[KittyStore] attachDebugger(pid) is no-op on simulator")
    #else
    print("[KittyStore] attachDebugger(pid) invoked")
    try Minimuxer.attachDebugger(pid: pid)
    #endif
}

func startAutoMounter(_ docsPath: String) {
    defer { print("[KittyStore] startAutoMounter(docsPath) completed") }
    #if targetEnvironment(simulator)
    print("[KittyStore] startAutoMounter(docsPath) is no-op on simulator")
    #else
    print("[KittyStore] startAutoMounter(docsPath) invoked")
    Minimuxer.startAutoMounter(docsPath: docsPath)
    #endif
}

func dumpProfiles(_ docsPath: String) throws -> String {
    defer { print("[KittyStore] dumpProfiles(docsPath) completed") }
    #if targetEnvironment(simulator)
    print("[KittyStore] dumpProfiles(docsPath) is no-op on simulator")
    return ""
    #else
    print("[KittyStore] dumpProfiles(docsPath) invoked")
    return try Minimuxer.dumpProfiles(docsPath: docsPath)
    #endif
}

func setMinimuxerDebug(_ debug: Bool) {
    defer { print("[KittyStore] setMinimuxerDebug(debug) completed") }
    print("[KittyStore] setMinimuxerDebug(debug) invoked")
    Minimuxer.setDebug(debug)
}

extension MinimuxerError: @retroactive LocalizedError {
    public var failureReason: String? {
        switch self {
        case .NoDevice:
            return NSLocalizedString("Cannot fetch the device from the muxer", comment: "")
        case .NoConnection:
            return NSLocalizedString("Unable to connect to the device, make sure LocalDevVPN is enabled and you're connected to Wi-Fi. This could mean an invalid pairing.", comment: "")
        case .PairingFile:
            return NSLocalizedString("Invalid pairing file. Your pairing file either didn't have a UDID, or it wasn't a valid plist. Please use iloader to replace it.", comment: "")
        case .CreateDebug:
            return createService(name: "debug")
        case .LookupApps:
            return getFromDevice(name: "installed apps")
        case .FindApp:
            return getFromDevice(name: "path to the app")
        case .BundlePath:
            return getFromDevice(name: "bundle path")
        case .MaxPacket:
            return setArgument(name: "max packet")
        case .WorkingDirectory:
            return setArgument(name: "working directory")
        case .Argv:
            return setArgument(name: "argv")
        case .LaunchSuccess:
            return getFromDevice(name: "launch success")
        case .Detach:
            return NSLocalizedString("Unable to detach from the app's process", comment: "")
        case .Attach:
            return NSLocalizedString("Unable to attach to the app's process", comment: "")
        case .CreateInstproxy:
            return createService(name: "instproxy")
        case .CreateAfc:
            return createService(name: "AFC")
        case .RwAfc:
            return NSLocalizedString("AFC was unable to manage files on the device.", comment: "")
        case .InstallApp(let message):
            return NSLocalizedString("Unable to install the app: \(message)", comment: "")
        case .UninstallApp:
            return NSLocalizedString("Unable to uninstall the app", comment: "")
        case .CreateMisagent:
            return createService(name: "misagent")
        case .ProfileInstall:
            return NSLocalizedString("Unable to manage profiles on the device", comment: "")
        case .ProfileRemove:
            return NSLocalizedString("Unable to manage profiles on the device", comment: "")
        case .CreateLockdown:
            return NSLocalizedString("Unable to connect to lockdown", comment: "")
        case .CreateCoreDevice:
            return NSLocalizedString("Unable to connect to core device proxy", comment: "")
        case .CreateSoftwareTunnel:
            return NSLocalizedString("Unable to create software tunnel", comment: "")
        case .CreateRemoteServer:
            return NSLocalizedString("Unable to connect to remote server", comment: "")
        case .CreateProcessControl:
            return NSLocalizedString("Unable to connect to process control", comment: "")
        case .GetLockdownValue:
            return NSLocalizedString("Unable to get value from lockdown", comment: "")
        case .Connect:
            return NSLocalizedString("Unable to connect to TCP port", comment: "")
        case .Close:
            return NSLocalizedString("Unable to close TCP port", comment: "")
        case .XpcHandshake:
            return NSLocalizedString("Unable to get services from XPC", comment: "")
        case .NoService:
            return NSLocalizedString("Device did not contain service", comment: "")
        case .InvalidProductVersion:
            return NSLocalizedString("Service version was in an unexpected format", comment: "")
        case .CreateFolder:
            return NSLocalizedString("Unable to create DDI folder", comment: "")
        case .DownloadImage:
            return NSLocalizedString("Unable to download DDI", comment: "")
        case .ImageLookup:
            return NSLocalizedString("Unable to lookup DDI images", comment: "")
        case .ImageRead:
            return NSLocalizedString("Unable to read images to memory", comment: "")
        case .Mount:
            return NSLocalizedString("Mount failed", comment: "")
        }
    }

    fileprivate func createService(name: String) -> String {
        String(format: NSLocalizedString("Cannot start a %@ server on the device.", comment: ""), name)
    }

    fileprivate func getFromDevice(name: String) -> String {
        String(format: NSLocalizedString("Cannot fetch %@ from the device.", comment: ""), name)
    }

    fileprivate func setArgument(name: String) -> String {
        String(format: NSLocalizedString("Cannot set %@ on the device.", comment: ""), name)
    }
}
