//
//  Install.swift
//  Minimuxer
//
//  Original Rust Implementation by @jkcoxson
//  Swift Port created by Magesh K on 02/03/26.
//

import Foundation
import RustBridge

public protocol InstallProvider {
    func yeetAppAfc(bundleId: String, ipaBytes: Data) throws
    func installIpa(bundleId: String) throws
    func removeApp(bundleId: String) throws
}

public class Install {
    public static var provider: InstallProvider?;
    
    private static func getProvider() throws -> any InstallProvider {
        if let provider {
            return provider
        } else {
            if Muxer.isrppairing {
                provider = RPInstall()
            } else {
                provider = LockDownInstall()
            }
        }
        return provider!
    }

    public static func yeetAppAfc(bundleId: String, ipaBytes: Data) throws {
        try getProvider().yeetAppAfc(bundleId: bundleId, ipaBytes: ipaBytes)
    }
    public static func installIpa(bundleId: String) throws {
        try getProvider().installIpa(bundleId: bundleId)
    }
    public static func removeApp(bundleId: String) throws {
        try getProvider().removeApp(bundleId: bundleId)
    }
}

public class LockDownInstall: InstallProvider {
    public func yeetAppAfc(bundleId: String, ipaBytes: Data) throws {
        print("[minimuxer] Yeeting IPA for bundle ID: \(bundleId)")

        let deviceIP = try DeviceEndpoint.shared.ip()
        print("[minimuxer] AFC: verifying device connectivity at \(deviceIP)...")
        guard Minimuxer.testDeviceConnection(ifaddr: deviceIP) else {
            print("[minimuxer] ERROR: Device not reachable before AFC start")
            throw MinimuxerError.NoConnection
        }
        print("[minimuxer] AFC: device reachable, fetching device handle")

        let device = try Device.getFirstDevice()
        print("[minimuxer] AFC: creating AFC client...")
        guard let afc = RustAfc.connect(device: device.internalInstance, label: "minimuxer") else {
            print("[minimuxer] ERROR: Could not start AFC service")
            throw MinimuxerError.CreateAfc
        }
        print("[minimuxer] AFC: client created successfully")

        let pkg = MuxerConstants.pkgPath
        let appDir = "./\(pkg)/\(bundleId)"
        mkdirP(appDir, afc: afc)

        if !afc.writeFile(path: "\(appDir)/app.ipa", data: ipaBytes) {
            print("[minimuxer] ERROR: Unable to write IPA to device")
            throw MinimuxerError.RwAfc
        }
        print("[minimuxer] Successfully staged IPA")
    }
    
    private func mkdirP(_ path: String, afc: RustAfc) {
        var current = ""
        for part in path.split(separator: "/") {
            current += "/\(part)"
            _ = afc.mkdir(path: current)
        }
    }

    public func installIpa(bundleId: String) throws {
        print("[minimuxer] Installing app for bundle ID: \(bundleId)")
        let device = try Device.getFirstDevice()
        guard let inst = RustInstProxy.connect(device: device.internalInstance, label: "ideviceinstaller") else {
            print("[minimuxer] ERROR: Unable to start instproxy")
            throw MinimuxerError.CreateInstproxy
        }
        let path = "./\(MuxerConstants.pkgPath)/\(bundleId)/app.ipa"
        print("[minimuxer] Installing...")
        if !inst.install(path: path) {
            print("[minimuxer] ERROR: Install failed")
            throw MinimuxerError.InstallApp("Failed to install")
        }
        print("[minimuxer] Install done!")
    }

    public func removeApp(bundleId: String) throws {
        print("[minimuxer] Removing app: \(bundleId)")
        let device = try Device.getFirstDevice()
        guard let inst = RustInstProxy.connect(device: device.internalInstance, label: "minimuxer-remove-app") else {
            print("[minimuxer] ERROR: Unable to start instproxy")
            throw MinimuxerError.CreateInstproxy
        }
        print("[minimuxer] Removing...")
        if !inst.uninstall(bundleId: bundleId) {
            print("[minimuxer] ERROR: Unable to uninstall app")
            throw MinimuxerError.UninstallApp
        }
        print("[minimuxer] Remove done!")
    }
}

public class RPInstall: InstallProvider {
    public func yeetAppAfc(bundleId: String, ipaBytes: Data) throws {
        try RustIdevice.yeetAppAfc(bundleId: bundleId, ipaBytes: ipaBytes)
    }
    public func installIpa(bundleId: String) throws {
        try RustIdevice.installIpa(bundleId: bundleId)
    }
    public func removeApp(bundleId: String) throws {
        try RustIdevice.removeApp(bundleId: bundleId)
    }
}
