//
//  Heartbeat.swift
//  Minimuxer
//
//  Original Rust Implementation by @jkcoxson
//  Swift Port created by Magesh K on 02/03/26.
//

import Foundation
import RustBridge

public class Heartbeat {
    public static var lastBeatSuccessful = false

    public static func startBeat() {
        Thread.detachNewThread {
            print("[minimuxer] Starting heartbeat thread...")
            while !Muxer.usbmuxdReady {
                Thread.sleep(forTimeInterval: 1)
                let ts = ISO8601DateFormatter().string(from: Date())
                print("[\(ts)] [minimuxer] heartbeat-thread: Waiting for usbmuxd to be ready...")
            }
            print("[minimuxer] heartbeat-thread: usbmuxd is ready")

            // outer loop
            while true {
                let deviceIP: String
                do {
                    deviceIP = try DeviceEndpoint.shared.ip()
                } catch {
                    print("[minimuxer] heartbeat-thread: deviceIP unavailable")
                    lastBeatSuccessful = false
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }
                
                // verify tunnel/device reachability first
                if !Minimuxer.testDeviceConnection(ifaddr: deviceIP) {
                    print("[minimuxer] heartbeat-thread: device IP not reachable, waiting...")
                    lastBeatSuccessful = false
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }
                print("[minimuxer] heartbeat-thread: device IP reachable at: \(deviceIP)")

                let device: Device
                do {
                    device = try Device.getFirstDevice()
                } catch {
                    print("[minimuxer] WARN: Could not query device from usbmuxd for heartbeat")
                    lastBeatSuccessful = false
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }

                guard let heartbeat = RustHeartbeat.connect(device: device.internalInstance, label: "minimuxer") else {
                    print("[minimuxer] ERROR: Failed to create heartbeat client")
                    lastBeatSuccessful = false
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }

                // Inner loop: keep receiving and sending heartbeats
                while true {
                   guard let plist = heartbeat.receive(timeoutMs: MuxerConstants.heartbeatTimeoutMs) else {
                       print("[minimuxer] ERROR: Heartbeat recv failed")
                       lastBeatSuccessful = false
                       break
                   }

                    if heartbeat.send(plistXml: plist) {
                        lastBeatSuccessful = true
                    } else {
                        print("[minimuxer] ERROR: Heartbeat send failed")
                        lastBeatSuccessful = false
                        break
                    }
                }
            }
        }
    }
}
