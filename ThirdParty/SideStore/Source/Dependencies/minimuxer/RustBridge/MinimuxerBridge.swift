//
//  MinimuxerBridge.swift
//  RustBridge(Minimuxer)
//
//  Created by Magesh K on 02/03/26.
//

import Foundation

// MARK: - FFI Declarations

@_silgen_name("rust_bridge_free_string")
internal func _rust_bridge_free_string(_ ptr: UnsafeMutablePointer<Int8>?)

@_silgen_name("rust_bridge_free_pointer")
internal func _rust_bridge_free_pointer(_ ptr: UnsafeMutableRawPointer?)

@_silgen_name("rust_bridge_free_byte_array")
internal func _rust_bridge_free_byte_array(_ ptr: UnsafeMutablePointer<UInt8>?, _ len: UInt32)

// Device
@_silgen_name("rust_bridge_device_get_first")
internal func _rust_bridge_device_get_first() -> UnsafeMutableRawPointer?

@_silgen_name("rust_bridge_device_get_udid")
internal func _rust_bridge_device_get_udid(_ device: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<Int8>?

// Lockdown
@_silgen_name("rust_bridge_lockdown_new")
internal func _rust_bridge_lockdown_new(_ device: UnsafeMutableRawPointer?, _ label: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer?

@_silgen_name("rust_bridge_lockdown_get_value")
internal func _rust_bridge_lockdown_get_value(_ client: UnsafeMutableRawPointer?, _ domain: UnsafePointer<Int8>?, _ key: UnsafePointer<Int8>?) -> UnsafeMutablePointer<Int8>?

// AFC
@_silgen_name("rust_bridge_afc_new")
internal func _rust_bridge_afc_new(_ device: UnsafeMutableRawPointer?, _ label: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer?

@_silgen_name("rust_bridge_afc_remove")
internal func _rust_bridge_afc_remove(_ client: UnsafeMutableRawPointer?, _ path: UnsafePointer<Int8>?) -> Bool

@_silgen_name("rust_bridge_afc_mkdir")
internal func _rust_bridge_afc_mkdir(_ client: UnsafeMutableRawPointer?, _ path: UnsafePointer<Int8>?) -> Bool

@_silgen_name("rust_bridge_afc_file_open")
internal func _rust_bridge_afc_file_open(_ client: UnsafeMutableRawPointer?, _ path: UnsafePointer<Int8>?, _ mode: UnsafePointer<Int8>?) -> UInt64

@_silgen_name("rust_bridge_afc_file_write")
internal func _rust_bridge_afc_file_write(_ client: UnsafeMutableRawPointer?, _ handle: UInt64, _ data: UnsafePointer<UInt8>?, _ size: UInt32) -> Bool

@_silgen_name("rust_bridge_afc_file_read")
internal func _rust_bridge_afc_file_read(_ client: UnsafeMutableRawPointer?, _ handle: UInt64, _ size: UInt32, _ outLen: UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<UInt8>?

@_silgen_name("rust_bridge_afc_file_close")
internal func _rust_bridge_afc_file_close(_ client: UnsafeMutableRawPointer?, _ handle: UInt64)

@_silgen_name("rust_bridge_afc_get_file_info")
internal func _rust_bridge_afc_get_file_info(_ client: UnsafeMutableRawPointer?, _ path: UnsafePointer<Int8>?) -> UnsafeMutablePointer<Int8>?

@_silgen_name("rust_bridge_afc_read_directory")
internal func _rust_bridge_afc_read_directory(_ client: UnsafeMutableRawPointer?, _ path: UnsafePointer<Int8>?) -> UnsafeMutablePointer<Int8>?

// InstProxy
@_silgen_name("rust_bridge_instproxy_new")
internal func _rust_bridge_instproxy_new(_ device: UnsafeMutableRawPointer?, _ label: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer?

@_silgen_name("rust_bridge_instproxy_install")
internal func _rust_bridge_instproxy_install(_ client: UnsafeMutableRawPointer?, _ path: UnsafePointer<Int8>?) -> Bool

@_silgen_name("rust_bridge_instproxy_uninstall")
internal func _rust_bridge_instproxy_uninstall(_ client: UnsafeMutableRawPointer?, _ bundle_id: UnsafePointer<Int8>?) -> Bool

@_silgen_name("rust_bridge_instproxy_lookup")
internal func _rust_bridge_instproxy_lookup(_ client: UnsafeMutableRawPointer?, _ app_id: UnsafePointer<Int8>?) -> UnsafeMutablePointer<Int8>?

@_silgen_name("rust_bridge_instproxy_get_path_for_bundle_identifier")
internal func _rust_bridge_instproxy_get_path_for_bundle_identifier(_ client: UnsafeMutableRawPointer?, _ bundle_id: UnsafePointer<Int8>?) -> UnsafeMutablePointer<Int8>?

// Misagent
@_silgen_name("rust_bridge_misagent_new")
internal func _rust_bridge_misagent_new(_ device: UnsafeMutableRawPointer?, _ label: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer?

@_silgen_name("rust_bridge_misagent_install")
internal func _rust_bridge_misagent_install(_ client: UnsafeMutableRawPointer?, _ profile_ptr: UnsafePointer<UInt8>?, _ size: UInt32) -> Bool

@_silgen_name("rust_bridge_misagent_remove")
internal func _rust_bridge_misagent_remove(_ client: UnsafeMutableRawPointer?, _ profile_id: UnsafePointer<Int8>?) -> Bool

@_silgen_name("rust_bridge_misagent_copy_all")
internal func _rust_bridge_misagent_copy_all(_ client: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<Int8>?

// Debugserver
@_silgen_name("rust_bridge_debugserver_new")
internal func _rust_bridge_debugserver_new(_ device: UnsafeMutableRawPointer?, _ label: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer?

@_silgen_name("rust_bridge_debugserver_send_command")
internal func _rust_bridge_debugserver_send_command(_ client: UnsafeMutableRawPointer?, _ command: UnsafePointer<Int8>?) -> UnsafeMutablePointer<Int8>?

@_silgen_name("rust_bridge_debugserver_set_argv")
internal func _rust_bridge_debugserver_set_argv(_ client: UnsafeMutableRawPointer?, _ argv_json: UnsafePointer<Int8>?) -> Bool

// MobileImageMounter
@_silgen_name("rust_bridge_mounter_new")
internal func _rust_bridge_mounter_new(_ device: UnsafeMutableRawPointer?, _ label: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer?

@_silgen_name("rust_bridge_mounter_lookup")
internal func _rust_bridge_mounter_lookup(_ client: UnsafeMutableRawPointer?, _ image_type: UnsafePointer<Int8>?) -> UnsafeMutablePointer<Int8>?

@_silgen_name("rust_bridge_mounter_upload")
internal func _rust_bridge_mounter_upload(_ client: UnsafeMutableRawPointer?, _ path: UnsafePointer<Int8>?, _ signature: UnsafePointer<Int8>?, _ image_type: UnsafePointer<Int8>?) -> Bool

@_silgen_name("rust_bridge_mounter_mount")
internal func _rust_bridge_mounter_mount(_ client: UnsafeMutableRawPointer?, _ path: UnsafePointer<Int8>?, _ signature: UnsafePointer<Int8>?, _ image_type: UnsafePointer<Int8>?) -> Bool

// Heartbeat
@_silgen_name("rust_bridge_heartbeat_new")
internal func _rust_bridge_heartbeat_new(_ device: UnsafeMutableRawPointer?, _ label: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer?

@_silgen_name("rust_bridge_heartbeat_receive")
internal func _rust_bridge_heartbeat_receive(_ client: UnsafeMutableRawPointer?, _ timeout_ms: UInt32) -> UnsafeMutablePointer<Int8>?

@_silgen_name("rust_bridge_heartbeat_send")
internal func _rust_bridge_heartbeat_send(_ client: UnsafeMutableRawPointer?, _ plist_xml: UnsafePointer<Int8>?) -> Bool

// Utility
@_silgen_name("rust_bridge_set_debug")
internal func _rust_bridge_set_debug(_ level: Int32)


// MARK: - Swift Wrappers

public final class RustDevice {
    internal let ptr: UnsafeMutableRawPointer
    init(ptr: UnsafeMutableRawPointer) { self.ptr = ptr }
    deinit { _rust_bridge_free_pointer(ptr) }
    public static func fetchFirst() -> RustDevice? {
        guard let p = _rust_bridge_device_get_first() else { return nil }
        return RustDevice(ptr: p)
    }
    public func getUDID() -> String? {
        guard let p = _rust_bridge_device_get_udid(ptr) else { return nil }
        defer { _rust_bridge_free_string(p) }
        return String(cString: p)
    }
}

public final class RustLockdown {
    internal let ptr: UnsafeMutableRawPointer
    init(ptr: UnsafeMutableRawPointer) { self.ptr = ptr }
    deinit { _rust_bridge_free_pointer(ptr) }
    public static func connect(device: RustDevice, label: String) -> RustLockdown? {
        guard let p = _rust_bridge_lockdown_new(device.ptr, label) else { return nil }
        return RustLockdown(ptr: p)
    }
    public func getValue(domain: String? = nil, key: String) -> String? {
        guard let p = _rust_bridge_lockdown_get_value(ptr, domain, key) else { return nil }
        defer { _rust_bridge_free_string(p) }
        return String(cString: p)
    }
}

public final class RustAfc {
    internal let ptr: UnsafeMutableRawPointer
    init(ptr: UnsafeMutableRawPointer) { self.ptr = ptr }
    deinit { _rust_bridge_free_pointer(ptr) }
    public static func connect(device: RustDevice, label: String) -> RustAfc? {
        guard let p = _rust_bridge_afc_new(device.ptr, label) else { return nil }
        return RustAfc(ptr: p)
    }
    public func remove(path: String) -> Bool {
        return _rust_bridge_afc_remove(ptr, path)
    }
    public func mkdir(path: String) -> Bool {
        return _rust_bridge_afc_mkdir(ptr, path)
    }
    public func fileOpen(path: String, mode: String) -> UInt64 {
        return _rust_bridge_afc_file_open(ptr, path, mode)
    }
    public func fileWrite(handle: UInt64, data: Data) -> Bool {
        return data.withUnsafeBytes { buf in
            _rust_bridge_afc_file_write(ptr, handle, buf.bindMemory(to: UInt8.self).baseAddress, UInt32(data.count))
        }
    }
    public func fileRead(handle: UInt64, size: UInt32) -> Data? {
        var outLen: UInt32 = 0
        guard let bytes = _rust_bridge_afc_file_read(ptr, handle, size, &outLen), outLen > 0 else { return nil }
        let data = Data(bytes: bytes, count: Int(outLen))
        _rust_bridge_free_byte_array(bytes, outLen)
        return data
    }
    public func fileClose(handle: UInt64) {
        _rust_bridge_afc_file_close(ptr, handle)
    }
    public func writeFile(path: String, data: Data) -> Bool {
        let handle = fileOpen(path: path, mode: "w")
        guard handle != 0 else { return false }
        defer { fileClose(handle: handle) }
        return fileWrite(handle: handle, data: data)
    }
    public func getFileInfo(path: String) -> [String: String]? {
        guard let p = _rust_bridge_afc_get_file_info(ptr, path) else { return nil }
        defer { _rust_bridge_free_string(p) }
        let jsonStr = String(cString: p)
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        return dict
    }
    public func readDirectory(path: String) -> [String]? {
        guard let p = _rust_bridge_afc_read_directory(ptr, path) else { return nil }
        defer { _rust_bridge_free_string(p) }
        let jsonStr = String(cString: p)
        guard let data = jsonStr.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return nil }
        return arr
    }
}

public final class RustInstProxy {
    internal let ptr: UnsafeMutableRawPointer
    init(ptr: UnsafeMutableRawPointer) { self.ptr = ptr }
    deinit { _rust_bridge_free_pointer(ptr) }
    public static func connect(device: RustDevice, label: String) -> RustInstProxy? {
        guard let p = _rust_bridge_instproxy_new(device.ptr, label) else { return nil }
        return RustInstProxy(ptr: p)
    }
    public func install(path: String) -> Bool {
        return _rust_bridge_instproxy_install(ptr, path)
    }
    public func uninstall(bundleId: String) -> Bool {
        return _rust_bridge_instproxy_uninstall(ptr, bundleId)
    }
    public func lookup(appId: String) -> String? {
        guard let p = _rust_bridge_instproxy_lookup(ptr, appId) else { return nil }
        defer { _rust_bridge_free_string(p) }
        return String(cString: p)
    }
    public func getPathForBundleIdentifier(bundleId: String) -> String? {
        guard let p = _rust_bridge_instproxy_get_path_for_bundle_identifier(ptr, bundleId) else { return nil }
        defer { _rust_bridge_free_string(p) }
        return String(cString: p)
    }
}

public final class RustMisagent {
    internal let ptr: UnsafeMutableRawPointer
    init(ptr: UnsafeMutableRawPointer) { self.ptr = ptr }
    deinit { _rust_bridge_free_pointer(ptr) }
    public static func connect(device: RustDevice, label: String) -> RustMisagent? {
        guard let p = _rust_bridge_misagent_new(device.ptr, label) else { return nil }
        return RustMisagent(ptr: p)
    }
    public func install(profileData: Data) -> Bool {
        return profileData.withUnsafeBytes { buf in
            _rust_bridge_misagent_install(ptr, buf.bindMemory(to: UInt8.self).baseAddress, UInt32(profileData.count))
        }
    }
    public func remove(profileId: String) -> Bool {
        return _rust_bridge_misagent_remove(ptr, profileId)
    }
    public func copyAll() -> String? {
        guard let p = _rust_bridge_misagent_copy_all(ptr) else { return nil }
        defer { _rust_bridge_free_string(p) }
        return String(cString: p)
    }
}

public final class RustDebugserver {
    internal let ptr: UnsafeMutableRawPointer
    init(ptr: UnsafeMutableRawPointer) { self.ptr = ptr }
    deinit { _rust_bridge_free_pointer(ptr) }
    public static func connect(device: RustDevice, label: String) -> RustDebugserver? {
        guard let p = _rust_bridge_debugserver_new(device.ptr, label) else { return nil }
        return RustDebugserver(ptr: p)
    }
    public func sendCommand(_ command: String) -> String? {
        guard let p = _rust_bridge_debugserver_send_command(ptr, command) else { return nil }
        defer { _rust_bridge_free_string(p) }
        return String(cString: p)
    }
    public func setArgv(_ argv: [String]) -> Bool {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: argv),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return false }
        return _rust_bridge_debugserver_set_argv(ptr, jsonStr)
    }
}

public final class RustMounter {
    internal let ptr: UnsafeMutableRawPointer
    init(ptr: UnsafeMutableRawPointer) { self.ptr = ptr }
    deinit { _rust_bridge_free_pointer(ptr) }
    public static func connect(device: RustDevice, label: String) -> RustMounter? {
        guard let p = _rust_bridge_mounter_new(device.ptr, label) else { return nil }
        return RustMounter(ptr: p)
    }
    public func lookup(imageType: String) -> String? {
        guard let p = _rust_bridge_mounter_lookup(ptr, imageType) else { return nil }
        defer { _rust_bridge_free_string(p) }
        return String(cString: p)
    }
    public func upload(path: String, signature: String, imageType: String) -> Bool {
        return _rust_bridge_mounter_upload(ptr, path, signature, imageType)
    }
    public func mount(path: String, signature: String, imageType: String) -> Bool {
        return _rust_bridge_mounter_mount(ptr, path, signature, imageType)
    }
}

public final class RustHeartbeat {
    internal let ptr: UnsafeMutableRawPointer
    init(ptr: UnsafeMutableRawPointer) { self.ptr = ptr }
    deinit { _rust_bridge_free_pointer(ptr) }
    public static func connect(device: RustDevice, label: String) -> RustHeartbeat? {
        guard let p = _rust_bridge_heartbeat_new(device.ptr, label) else { return nil }
        return RustHeartbeat(ptr: p)
    }
    public func receive(timeoutMs: UInt32) -> String? {
        guard let p = _rust_bridge_heartbeat_receive(ptr, timeoutMs) else { return nil }
        defer { _rust_bridge_free_string(p) }
        return String(cString: p)
    }
    public func send(plistXml: String) -> Bool {
        return _rust_bridge_heartbeat_send(ptr, plistXml)
    }
}

// MARK: - Utility

@_silgen_name("rust_bridge_debug_app_post17")
internal func _rust_bridge_debug_app_post17(_ app_id: UnsafePointer<Int8>?, _ muxer_addr: UnsafePointer<Int8>?, _ device_ip: UnsafePointer<Int8>?) -> Int32

@_silgen_name("rust_bridge_mount_personalized_ddi")
internal func _rust_bridge_mount_personalized_ddi(
    _ image_ptr: UnsafePointer<UInt8>?, _ image_len: UInt32,
    _ trustcache_ptr: UnsafePointer<UInt8>?, _ trustcache_len: UInt32,
    _ manifest_ptr: UnsafePointer<UInt8>?, _ manifest_len: UInt32,
    _ muxer_addr: UnsafePointer<Int8>?, _ device_ip: UnsafePointer<Int8>?
) -> Int32

public func rustBridgeSetDebug(_ debug: Bool) {
    _rust_bridge_set_debug(debug ? 1 : 0)
}

/// Post-iOS-17 JIT debug via CoreDeviceProxy + DVT + DebugProxy.
public func rustBridgeDebugAppPost17(_ appId: String, muxerAddr: String, deviceIp: String) -> Int32 {
    return _rust_bridge_debug_app_post17(appId, muxerAddr, deviceIp)
}

/// Post-iOS-17 personalized DDI mount from already-downloaded file bytes.
/// Swift is responsible for downloading the DDI files.
public func rustBridgeMountPersonalizedDDI(image: Data, trustcache: Data, manifest: Data, muxerAddr: String, deviceIp: String) -> Int32 {
    return image.withUnsafeBytes { imgBuf in
        trustcache.withUnsafeBytes { tcBuf in
            manifest.withUnsafeBytes { manBuf in
                _rust_bridge_mount_personalized_ddi(
                    imgBuf.bindMemory(to: UInt8.self).baseAddress, UInt32(image.count),
                    tcBuf.bindMemory(to: UInt8.self).baseAddress, UInt32(trustcache.count),
                    manBuf.bindMemory(to: UInt8.self).baseAddress, UInt32(manifest.count),
                    muxerAddr, deviceIp
                )
            }
        }
    }
}

