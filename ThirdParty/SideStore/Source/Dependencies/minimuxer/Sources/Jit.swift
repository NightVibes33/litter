//
//  Jit.swift
//  Minimuxer
//
//  Original Rust Implementation by @jkcoxson
//  Swift Port created by Magesh K on 02/03/26.
//

import Foundation
import RustBridge

public protocol JITProvider {
    func debugApp(appId: String) throws;
    func attachDebugger(pid: UInt32) throws;
}

public class JIT {
    private static var provider: JITProvider?;
    
    private static func getProvider() -> any JITProvider {
        if let provider {
            return provider
        } else {
            if Muxer.isrppairing {
                provider = RPJit()
            } else {
                provider = LockDownJIT()
            }
        }
        
        return provider!
    }

    public static func debugApp(appId: String) throws {
        try getProvider().debugApp(appId: appId)
    }
    
    public static func attachDebugger(pid: UInt32) throws {
        try getProvider().attachDebugger(pid: pid)
    }
}

public class LockDownJIT: JITProvider {
    public func debugApp(appId: String) throws {
        print("[minimuxer] Debugging app ID: \(appId)")
        let device = try Device.getFirstDevice()

        guard let lockdown = RustLockdown.connect(device: device.internalInstance, label: "minimuxer") else {
            print("[minimuxer] ERROR: Failed to connect to lockdown")
            throw MinimuxerError.CreateLockdown
        }

        guard let versionStr = lockdown.getValue(key: "ProductVersion") else {
            print("[minimuxer] ERROR: Failed to get product version from lockdown")
            throw MinimuxerError.GetLockdownValue
        }

        guard let majorStr = versionStr.split(separator: ".").first,
              let major = Int(majorStr) else {
            print("[minimuxer] ERROR: Failed to get product version from plist")
            throw MinimuxerError.InvalidProductVersion
        }

        if major < 17 {
            try debugPre17(device: device, appId: appId)
        } else {
            // iOS 17+ uses CoreDeviceProxy + DVT + DebugProxy via async Rust
            print("[minimuxer] iOS \(major) detected, using post-17 JIT path")
            let muxerAddr = "127.0.0.1:\(MuxerConstants.usbmuxdPort)"
            let result = rustBridgeDebugAppPost17(appId, muxerAddr: muxerAddr, deviceIp: try DeviceEndpoint.shared.ip())
            if result != 0 {
                switch result {
                case 1: throw MinimuxerError.NoConnection
                case 2: throw MinimuxerError.CreateCoreDevice
                case 3: throw MinimuxerError.CreateSoftwareTunnel
                case 4: throw MinimuxerError.Connect
                case 5: throw MinimuxerError.XpcHandshake
                case 6: throw MinimuxerError.NoService
                case 7: throw MinimuxerError.Close
                case 8: throw MinimuxerError.CreateRemoteServer
                case 9: throw MinimuxerError.CreateProcessControl
                case 10: throw MinimuxerError.LaunchSuccess
                case 11: throw MinimuxerError.Attach
                default: throw MinimuxerError.CreateCoreDevice
                }
            }
        }
    }

    private func debugPre17(device: Device, appId: String) throws {
        guard let debugServer = RustDebugserver.connect(device: device.internalInstance, label: "minimuxer") else {
            print("[minimuxer] ERROR: Failed to start debug server")
            throw MinimuxerError.CreateDebug
        }

        guard let instProxy = RustInstProxy.connect(device: device.internalInstance, label: "minimuxer") else {
            print("[minimuxer] ERROR: Failed to create instproxy client")
            throw MinimuxerError.CreateInstproxy
        }

        // Lookup app info
        guard let lookupResult = instProxy.lookup(appId: appId) else {
            print("[minimuxer] ERROR: App not found: \(appId)")
            throw MinimuxerError.LookupApps
        }

        // Parse the plist string to extract Container
        guard let plistData = lookupResult.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let container = plist["Container"] as? String else {
            print("[minimuxer] ERROR: Unable to find container for app")
            throw MinimuxerError.FindApp
        }
        print("[minimuxer] Working directory: \(container)")

        // Get bundle path
        guard let bundlePath = instProxy.getPathForBundleIdentifier(bundleId: appId) else {
            print("[minimuxer] ERROR: Error getting path for bundle identifier")
            throw MinimuxerError.BundlePath
        }
        print("[minimuxer] Found bundle path: \(bundlePath)")

        _ = debugServer.sendCommand("QSetMaxPacketSize:1024")
        _ = debugServer.sendCommand("QSetWorkingDir:\(container)")

        if !debugServer.setArgv([bundlePath, bundlePath]) {
            print("[minimuxer] ERROR: Error setting argv")
            throw MinimuxerError.Argv
        }

        _ = debugServer.sendCommand("qLaunchSuccess")
        print("[minimuxer] Detaching debugserver")
        _ = debugServer.sendCommand("D")
    }

    public func attachDebugger(pid: UInt32) throws {
        print("[minimuxer] Debugging process ID: \(pid)")
        let device = try Device.getFirstDevice()
        guard let debugServer = RustDebugserver.connect(device: device.internalInstance, label: "minimuxer") else {
            print("[minimuxer] ERROR: Failed to start debug server")
            throw MinimuxerError.CreateDebug
        }

        let command = "vAttach;\(String(format: "%08x", pid))"
        print("[minimuxer] Sending command: \(command)")
        _ = debugServer.sendCommand(command)
        _ = debugServer.sendCommand("D")
    }
}

public class RPJit: JITProvider {
    public func debugApp(appId: String) throws {
        try RustIdevice.debugApp(appId: appId)
    }
    
    public func attachDebugger(pid: UInt32) throws {
        try RustIdevice.debugApp(pid: pid)
    }
}
