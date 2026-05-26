//
//  NetworkObserver.swift
//  Minimuxer
//
//  Original Rust Implementation by @jkcoxson
//  Swift Port created by Magesh K on 02/03/26.
//

import Network
import Foundation

public final class NetworkObserver {

    public static let shared = NetworkObserver()   // keep alive

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "net.monitor")

    private var started = false
    private let lock = NSLock()

    @discardableResult
    public func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !started else {
            print("[minimuxer] [net] monitor already started")
            return false
        }

        monitor.pathUpdateHandler = { [weak self] path in
            print("[minimuxer] [net] path changed, status:", path.status)
            guard path.status == .satisfied else { return }
            self?.refreshEndpoint()
        }

        monitor.start(queue: queue)
        started = true
        print("[minimuxer] [net] monitor started")
        return true
    }
    
    public func refreshEndpoint() {
        print("[minimuxer] [net] refreshing interfaces list and peers")
        IfaceScanner.shared.refresh()

        print("[minimuxer] [net] retrive the first vpn interface info")
        if let info = try? IfaceScanner.shared.probableVPN() {
            print("[minimuxer] [net] vpn:", info, "peer:", info.peerIP ?? "nil")

            if let peer = info.peerIP {
                print("[minimuxer] [net] update the device endpoint with discovered peer on the vpn interface")
                DeviceEndpoint.shared.update(peer)
                Muxer.notifyDeviceAttached(deviceIP: peer)
            } else {
                print("[minimuxer] [net] peer not available for", info.name)
                DeviceEndpoint.shared.clear()
                Muxer.notifyDeviceDetached()
            }
        } else {
            print("[minimuxer] [net] no SideVPN endpoint detected")
            DeviceEndpoint.shared.clear()
            Muxer.notifyDeviceDetached()
        }
    }
    
    @discardableResult
    public func stop() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard started else {
            print("[minimuxer] [net] monitor already stopped")
            return false
        }

        monitor.cancel()
        started = false
        print("[minimuxer] [net] monitor stopped")
        return true
    }
}
