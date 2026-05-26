//
//  IfaceScanner.swift
//  Minimuxer
//
//  Created by ny on 2/27/26.
//  Copyright © 2026 SideStore. All rights reserved.
//


import Foundation
import Darwin

// MARK: - IPv4 helpers

@inline(__always)
private func ipv4String(_ value: UInt32) -> String? {
    var addr = in_addr(s_addr: value.bigEndian)
    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    guard inet_ntop(AF_INET, &addr, &buf, UInt32(INET_ADDRSTRLEN)) != nil else { return nil }
    return String(cString: buf)
}

@inline(__always)
private func sockaddrIPv4(_ sa: inout sockaddr) -> UInt32? {
    var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    guard getnameinfo(&sa, socklen_t(sa.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0,
          let s = String(validatingUTF8: buf) else { return nil }
    var a = in_addr()
    return inet_pton(AF_INET, s, &a) == 1 ? a.s_addr.bigEndian : nil
}

// MARK: - NetInfo


public struct NetInfo: Hashable, CustomStringConvertible {

    public let name: String
    public let hostIP: String
    public let maskIP: String

    fileprivate let host: UInt32
    fileprivate let mask: UInt32

    init?(ifa: ifaddrs) {
        guard
            let name = String(utf8String: ifa.ifa_name),
            var addr = ifa.ifa_addr?.pointee,
            var mask = ifa.ifa_netmask?.pointee,
            let host = sockaddrIPv4(&addr),
            let maskU = sockaddrIPv4(&mask),
            let hostStr = ipv4String(host),
            let maskStr = ipv4String(maskU)
        else { return nil }

        self.name = name
        self.host = host
        self.mask = maskU
        self.hostIP = hostStr
        self.maskIP = maskStr
    }
    
    var peerIP: String? {
        IfaceScanner.shared.getPeer(for: self).flatMap{ $0 }
    }

    var networkBase: UInt32 { host & mask }
    var broadcast: UInt32 { networkBase | ~mask }

    public var description: String {
        "\(name) | ip=\(hostIP) mask=\(maskIP)"
    }
    
}

public final class TunnelConfigBinding: Sendable {
    public let setDeviceIP: @Sendable (String?) -> Void
    public let setFakeIP: @Sendable (String?) -> Void
    public let setSubnetMask: @Sendable (String?) -> Void
    public let getOverrideFakeIP: @Sendable () -> String
    public let setOverrideEffective: @Sendable (Bool) -> Void

    public init(
        setDeviceIP: @escaping @Sendable (String?) -> Void,
        setFakeIP: @escaping @Sendable (String?) -> Void,
        setSubnetMask: @escaping @Sendable (String?) -> Void,
        getOverrideFakeIP: @escaping @Sendable () -> String,
        setOverrideEffective: @escaping @Sendable (Bool) -> Void
    ) {
        self.setDeviceIP = setDeviceIP
        self.setFakeIP = setFakeIP
        self.setSubnetMask = setSubnetMask
        self.getOverrideFakeIP = getOverrideFakeIP
        self.setOverrideEffective = setOverrideEffective
    }
}


final class IfaceScanner {

    static let shared = IfaceScanner()
    private(set) var interfaces: Set<NetInfo> = []

    private var refreshed = false
    private let lock = NSLock()

    private var tunnelConfigCache: TunnelConfigBinding?

    func bindTunnelConfig(_ binding: TunnelConfigBinding) {
        tunnelConfigCache = binding
        
        // ask all observers to be refreshed
        NetworkObserver.shared.refreshEndpoint()
    }

    var cachedOverrideFakeIP: String? { tunnelConfigCache?.getOverrideFakeIP() }
    
    private init() {}

    func refresh() {
        lock.lock(); defer { lock.unlock() }
        
        interfaces = Self.scan()
        refreshed = true

        let vpnIface = try? probableVPN()
        tunnelConfigCache?.setDeviceIP(vpnIface?.hostIP)
        tunnelConfigCache?.setSubnetMask(vpnIface?.maskIP)
        let peerIP = vpnIface?.peerIP
        let isOverrideActive = peerIP != nil && peerIP == cachedOverrideFakeIP
        tunnelConfigCache?.setFakeIP(peerIP)
        tunnelConfigCache?.setOverrideEffective(isOverrideActive)
        
        print("""
        [minimuxer] [iface] rescan routes
          • interfaces: \(interfaces.count)
          • vpn host: \(vpnIface?.hostIP ?? "nil")
          • vpn mask: \(vpnIface?.maskIP ?? "nil")
          • vpn peer: \(peerIP ?? "nil")
          • cachedOverrideFakeIP: \(cachedOverrideFakeIP ?? "nil")
          • overrideEffective: \(isOverrideActive)
          • refreshed: \(refreshed)
        """)
    }

    private func ensureReady() throws {
        guard refreshed else { throw IfaceError.notRefreshed }
    }

    // MARK: scan
    private static func scan() -> Set<NetInfo> {
        print("[minimuxer] [iface] scan requested...")

        var result = Set<NetInfo>()
        var head: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&head) == 0, let first = head else { return result }
        defer { freeifaddrs(head) }

        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            let e = p.pointee
            let flags = Int32(e.ifa_flags)

            let ipv4 = e.ifa_addr?.pointee.sa_family == UInt8(AF_INET)
            let active = (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING)

            if ipv4, active, let info = NetInfo(ifa: e) {
                print("[minimuxer] [iface]", info)
                result.insert(info)
            }

            cur = e.ifa_next
        }

        print("[minimuxer] [iface] total:", result.count)
        return result
    }
    
    
    public func getPeer(for iface: NetInfo) -> String? {
        if let cachedDeviceIP = cachedOverrideFakeIP {
            let reachable = Minimuxer.testDeviceConnection(ifaddr: cachedDeviceIP)
            if reachable {
                print("[minimuxer] [iface] override peer reachable at:", cachedDeviceIP)
                return cachedDeviceIP
            } else {
                print("[minimuxer] [iface] override peer NOT reachable at:", cachedDeviceIP)
                return nil
            }
        }
        print("[minimuxer] [iface] no override peer configured")
        return nil
    }

    // MARK: selection

    func probableVPN() throws -> NetInfo? {
        try ensureReady()
        return interfaces.first { $0.name.hasPrefix("utun") }
    }

    func probableLAN() throws -> NetInfo? {
        try ensureReady()
        return interfaces.first { $0.name.hasPrefix("en") }
    }

    func vpnPatched() -> Bool {
        guard let lan = try? probableLAN(),
              let vpn = try? probableVPN()
        else { return false }

        return lan.maskIP == vpn.maskIP
    }
}

enum IfaceError: Error {
    case notRefreshed
}
