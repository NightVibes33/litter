//
//  Device.swift
//  Minimuxer
//
//  Original Rust Implementation by @jkcoxson
//  Swift Port created by Magesh K on 02/03/26.
//

import Foundation
import RustBridge

public final class Device {
    private let rustDevice: RustDevice

    init(rustDevice: RustDevice) { self.rustDevice = rustDevice }

    public static func getFirstDevice() throws -> Device {
        var remaining = MuxerConstants.deviceFetchTimeoutMs
        let sleep = MuxerConstants.deviceFetchSleepMs

        while remaining > 0 {
            if let rd = RustDevice.fetchFirst() {
                return Device(rustDevice: rd)
            }
            Thread.sleep(forTimeInterval: Double(sleep) / 1000.0)
            remaining = remaining >= UInt16(sleep) ? remaining - UInt16(sleep) : 0
        }
        print("[minimuxer] ERROR: Couldn't fetch first device (timed out)")
        throw MinimuxerError.NoDevice
    }

    public func getUDID() -> String? { rustDevice.getUDID() }
    internal var internalInstance: RustDevice { rustDevice }
}
