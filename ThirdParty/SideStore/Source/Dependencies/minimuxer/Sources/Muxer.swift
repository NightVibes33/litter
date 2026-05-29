//
//  Muxer.swift
//  Minimuxer
//
//  Original Rust Implementation by @jkcoxson
//  Swift Port created by Magesh K on 02/03/26.
//

import Foundation
import RustBridge
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public class Muxer {
    public static var started = false
    public static var usbmuxdReady = false
    public static var isrppairing = false
    
    private static let DEVICE_ATTACH = "Attached"
    private static let DEVICE_DETACH = "Detached"

    private static var cachedPairingDict: [String: Any]?
    private static var cachedPairingXml: Data?

    // Stable device state
    private static var currentDeviceIP: String?
    private static var currentEvent: String?

    public static func retargetUsbmuxdAddr() {
        print("[minimuxer] unsetenv(USBMUXD_SOCKET_ADDRESS)")
        unsetenv(MuxerConstants.usbmuxdEnvKey)
        print("[minimuxer] setenv(USBMUXD_SOCKET_ADDRESS, \(MuxerConstants.usbmuxdSocket))")
        setenv(MuxerConstants.usbmuxdEnvKey, MuxerConstants.usbmuxdSocket, 1)
        let value = String(cString: getenv(MuxerConstants.usbmuxdEnvKey))
        print("[minimuxer] getenv(USBMUXD_SOCKET_ADDRESS) =", value)
    }

    public static func start(pairingFile: String, logPath: String) throws {
        if started {
            print("[minimuxer] Already started minimuxer, skipping")
            return
        }

        guard let pairingData = pairingFile.data(using: .utf8),
              let pairingDict = try? PropertyListSerialization.propertyList(from: pairingData, options: [], format: nil) as? [String: Any],
              let pairingXml  = try? PropertyListSerialization.data(fromPropertyList: pairingDict, format: .xml, options: 0)
        else {
            print("[minimuxer] ERROR: Failed to parse pairing file")
            throw MinimuxerError.PairingFile
        }
        
        let hasRemotePairingRecord = pairingDict["PairRecordData"] is Data && pairingDict["private_key"] is Data
        let hasLockdownPairingRecord = pairingDict["UDID"] is String

        guard hasRemotePairingRecord || hasLockdownPairingRecord else {
            print("[minimuxer] ERROR: Pairing file missing UDID or remote PairRecordData")
            throw MinimuxerError.PairingFile
        }

        cachedPairingDict = pairingDict
        cachedPairingXml  = pairingXml
        isrppairing = hasRemotePairingRecord
        Install.provider = nil

        do {
            if isrppairing {
                print("[minimuxer] INFO: RPPairing file detected")
                try RustIdevice.setRpPairingFile(pairingFile)
            } else {
                print("[minimuxer] INFO: Lockdown pairing file detected")
                Thread.detachNewThread { listenLoop() }
                Heartbeat.startBeat()
            }
            started = true
            print("[minimuxer] minimuxer has started!")
        } catch {
            cachedPairingDict = nil
            cachedPairingXml = nil
            isrppairing = false
            started = false
            Install.provider = nil
            throw error
        }
    }

    // MARK: - Listener

    // Binds a TCP server on 127.0.0.1:27015 and accepts incoming connections
    // from libimobiledevice/libusbmuxd. This is our fake usbmuxd — it speaks
    // just enough of the usbmuxd protocol for the library to discover the
    // device, read the pairing record, and open services (AFC, lockdown, etc.).
    private static func listenLoop() {
        while true {
            print("[minimuxer] Starting listener")

            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else {
                Thread.sleep(forTimeInterval: 1)
                continue
            }

            var yes = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int>.size))
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = MuxerConstants.usbmuxdPort.bigEndian
            addr.sin_addr.s_addr = inet_addr(MuxerConstants.usbmuxdHost)

            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            let value = String(cString: getenv(MuxerConstants.usbmuxdEnvKey))
            print("[minimuxer] muxer: (ENV) USBMUXD_SOCKET_ADDRESS =", value)

            guard bindResult == 0, listen(fd, 16) == 0 else {
                print("[minimuxer] WARN: Failed to bind/listen")
                close(fd)
                usbmuxdReady = false
                Thread.sleep(forTimeInterval: 1)
                continue
            }

            print("[minimuxer] Bound successfully to \(MuxerConstants.usbmuxdHost):\(MuxerConstants.usbmuxdPort)")
            usbmuxdReady = true

            // accept loop — runs until socket dies
            var consecutiveErrors = 0
            while true {
                var clientAddr = sockaddr()
                var addrLen = socklen_t(MemoryLayout<sockaddr>.size)
                let clientFd = accept(fd, &clientAddr, &addrLen)
                guard clientFd >= 0 else {
                    consecutiveErrors += 1
                    print("[minimuxer] WARN: accept() failed (\(consecutiveErrors)): \(String(cString: strerror(errno)))")
                    if consecutiveErrors > 0 {
                        print("[minimuxer] ERROR: accept() repeatedly failing, restarting socket")
                        break  // break inner → outer loop recreates socket
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                    continue
                }
                consecutiveErrors = 0

                var nosig = 1
                setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))

                Task.detached { handleClient(fd: clientFd) }
            }

            // socket died — close and let outer loop restart
            close(fd)
            usbmuxdReady = false
            print("[minimuxer] listener restarting...")
            Thread.sleep(forTimeInterval: 1)
        }
    }
    
    private static func handleClient(fd: Int32) {
        defer { close(fd) }

        let bufLen = 0xfff
        var buffer = [UInt8](repeating: 0, count: bufLen)

        while true {
            let bytesRead = recv(fd, &buffer, bufLen, 0)
            guard bytesRead > 0 else { return }
            var totalRead = bytesRead

            // libimobiledevice sometimes sends the 16-byte packet header in
            // one write and the plist body in a follow-up write. If we only
            // got the header, block for the body before trying to parse.
            if bytesRead == 16 {
                let extra = recv(fd, &buffer[16], bufLen - 16, 0)
                if extra > 0 { totalRead += extra }
            }

            let data = Data(buffer[0..<totalRead])
            guard let packet = RawPacket(data: data) else { return }

            do {
                let response = try handlePacket(packet, fd: fd)
                let responsePacket = RawPacket(plist: response, version: 1, message: 8, tag: packet.tag)
                let responseData = responsePacket.data
                responseData.withUnsafeBytes { ptr in
                    _ = send(fd, ptr.baseAddress!, responseData.count, 0)
                }
            } catch {}
        }
    }

    
    private static func buildPayload(deviceIP: String, event: String? = nil) throws -> [String: Any] {
        guard let udid = cachedPairingDict?["UDID"] as? String else {
            throw MinimuxerError.PairingFile
        }

        let networkAddr = convertIp(deviceIP)

        var payload: [String: Any] = [
            "DeviceID": 420,
            "Properties": [
                "ConnectionType": "Network",
                "DeviceID": 420,
                "EscapedFullServiceName": "\(udid)._apple-mobdev2._tcp.local",
                "InterfaceIndex": 69,
                "NetworkAddress": Data(networkAddr),
                "SerialNumber": udid
            ]
        ]

        if let event = event {
            payload["MessageType"] = event
        }

        return payload
    }
    
    // MARK: - Packet Handling

    // Responds to the subset of usbmuxd protocol messages that
    // libimobiledevice actually needs from us:
    private static func handlePacket(_ packet: RawPacket, fd: Int32) throws -> [String: Any] {
        guard let messageType = packet.plist["MessageType"] as? String else {
            throw MinimuxerError.NoConnection
        }

        print("[minimuxer] usbmux message:", messageType)

        switch messageType {
            case "ListDevices":
                guard let deviceIP = currentDeviceIP,
                      let payload = try? buildPayload(deviceIP: deviceIP) else {
                    return ["DeviceList": []]
                }
                return ["DeviceList": [payload]]
                
            case "Listen":
                if let deviceIP = currentDeviceIP{
                     Task.detached {
                         if let payload = try? buildPayload(deviceIP: deviceIP, event: currentEvent){
                             let pkt = RawPacket(plist: payload, version: 1, message: 8, tag: 0)
                             let data = pkt.data
                             data.withUnsafeBytes { _ = send(fd, $0.baseAddress!, data.count, 0) }
                         }
                     }
                }
                return ["MessageType": "Result", "Number": 0]
                
            case "ReadBUID":
                return ["BUID": "00000000-0000-0000-0000-000000000000"]

            case "ReadPairRecord":
                let pairingData = cachedPairingXml ?? Data()
                return ["PairRecordData": pairingData]

            default:
                print("[minimuxer] WARN: unknown message type:", messageType)
                throw MinimuxerError.NoConnection
        }
    }
    
    
    public static func notifyDeviceAttached(deviceIP: String){
        currentDeviceIP = deviceIP
        currentEvent = DEVICE_ATTACH
    }
    public static func notifyDeviceDetached(){
        currentDeviceIP = nil
        currentEvent = DEVICE_DETACH
    }


    private static func emitDeviceEvent(fd: Int32, type: String, payload: [String: Any]) {
        let plist: [String: Any] = [
            "MessageType": type,
            "DeviceID": payload["DeviceID"]!
        ]

        let pkt = RawPacket(plist: plist, version: 1, message: 8, tag: 0)
        let data = pkt.data
        data.withUnsafeBytes {
            _ = send(fd, $0.baseAddress!, data.count, 0)
        }
    }
    

    // MARK: - Helpers

    // Encodes an IPv4 address into the 152-byte sockaddr_storage layout that
    // libusbmuxd expects in the NetworkAddress field of the device properties.
    private static func convertIp(_ ip: String) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 152)
        var addr = in_addr()
        if inet_pton(AF_INET, ip, &addr) == 1 {
            data[0] = 10; data[1] = 0x02
            let ipBytes = withUnsafeBytes(of: &addr.s_addr) { Array($0) }
            for (i, byte) in ipBytes.enumerated() { data[4 + i] = byte }
        }
        return data
    }
}
