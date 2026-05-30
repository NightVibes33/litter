//
//  bridge.rs
//  RustBridge(Minimuxer)
//
//  Created by Magesh K on 02/03/26.
//

use crate::post17;
use plist_plus::Plist;
use rusty_libimobiledevice::idevice::{get_first_device, Device};
use rusty_libimobiledevice::services::afc::{AfcClient, AfcFileMode};
use rusty_libimobiledevice::services::debug_server::DebugServer;
use rusty_libimobiledevice::services::heartbeat::HeartbeatClient;
use rusty_libimobiledevice::services::instproxy::InstProxyClient;
use rusty_libimobiledevice::services::lockdownd::LockdowndClient;
use rusty_libimobiledevice::services::misagent::MisagentClient;
use rusty_libimobiledevice::services::mobile_image_mounter::MobileImageMounter;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};

fn to_char(s: String) -> *mut c_char {
    CString::new(s).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn rust_bridge_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_free_pointer(ptr: *mut c_void) {
    if !ptr.is_null() {
        unsafe {
            let _ = Box::from_raw(ptr);
        }
    }
}

// --- Device ---
pub struct DeviceWrapper(Device);

#[no_mangle]
pub extern "C" fn rust_bridge_device_get_first() -> *mut DeviceWrapper {
    match get_first_device() {
        Ok(d) => Box::into_raw(Box::new(DeviceWrapper(d))),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_device_get_udid(device: *mut DeviceWrapper) -> *mut c_char {
    let d = unsafe { &*device };
    to_char(d.0.get_udid())
}

// --- Lockdown ---
pub struct LockdownWrapper<'a>(LockdowndClient<'a>);

#[no_mangle]
pub extern "C" fn rust_bridge_lockdown_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut LockdownWrapper<'static> {
    let d = unsafe { &*device };
    let label = unsafe { CStr::from_ptr(label) }.to_str().unwrap();
    unsafe {
        match d.0.new_lockdownd_client(label) {
            Ok(c) => Box::into_raw(Box::new(LockdownWrapper(std::mem::transmute(c)))),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_lockdown_get_value(
    client: *mut LockdownWrapper,
    domain: *const c_char,
    key: *const c_char,
) -> *mut c_char {
    let c = unsafe { &*client };
    let domain = unsafe {
        if domain.is_null() {
            ""
        } else {
            CStr::from_ptr(domain).to_str().unwrap()
        }
    };
    let key = unsafe { CStr::from_ptr(key).to_str().unwrap() };
    match c.0.get_value(key, domain) {
        Ok(p) => match p.get_string_val() {
            Ok(s) => to_char(s),
            Err(_) => to_char(p.to_string()),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

// --- AFC ---
pub struct AfcWrapper<'a>(AfcClient<'a>);

#[no_mangle]
pub extern "C" fn rust_bridge_afc_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut AfcWrapper<'static> {
    let d = unsafe { &*device };
    let label = unsafe { CStr::from_ptr(label) }.to_str().unwrap();
    unsafe {
        match d.0.new_afc_client(label) {
            Ok(c) => Box::into_raw(Box::new(AfcWrapper(std::mem::transmute(c)))),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_remove(client: *mut AfcWrapper, path: *const c_char) -> bool {
    let c = unsafe { &*client };
    let path = unsafe { CStr::from_ptr(path).to_str().unwrap() };
    c.0.remove_path_and_contents(path).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_mkdir(client: *mut AfcWrapper, path: *const c_char) -> bool {
    let c = unsafe { &*client };
    let path = unsafe { CStr::from_ptr(path).to_str().unwrap() };
    c.0.make_directory(path).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_file_open(
    client: *mut AfcWrapper,
    path: *const c_char,
    mode: *const c_char,
) -> u64 {
    let c = unsafe { &*client };
    let path = unsafe { CStr::from_ptr(path).to_str().unwrap() };
    let mode_str = unsafe { CStr::from_ptr(mode).to_str().unwrap() };
    let mode = match mode_str {
        "r" | "rdonly" => AfcFileMode::ReadOnly,
        "w" | "wronly" => AfcFileMode::WriteOnly,
        "rw" | "rdwr" => AfcFileMode::ReadWrite,
        _ => AfcFileMode::ReadOnly,
    };
    match c.0.file_open(path, mode) {
        Ok(handle) => handle,
        Err(_) => 0,
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_file_write(
    client: *mut AfcWrapper,
    handle: u64,
    data: *const u8,
    size: u32,
) -> bool {
    let c = unsafe { &*client };
    let data = unsafe { std::slice::from_raw_parts(data, size as usize) };
    c.0.file_write(handle, data.to_vec()).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_file_read(
    client: *mut AfcWrapper,
    handle: u64,
    size: u32,
    out_len: *mut u32,
) -> *mut u8 {
    let c = unsafe { &*client };
    match c.0.file_read(handle, size) {
        Ok(data) => {
            let data: Vec<u8> = data.into_iter().map(|b| b as u8).collect();
            let len = data.len() as u32;
            unsafe {
                *out_len = len;
            }
            let mut boxed = data.into_boxed_slice();
            let ptr = boxed.as_mut_ptr();
            std::mem::forget(boxed);
            ptr
        }
        Err(_) => {
            unsafe {
                *out_len = 0;
            }
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_free_byte_array(ptr: *mut u8, len: u32) {
    if !ptr.is_null() {
        unsafe {
            let _ = Vec::from_raw_parts(ptr, len as usize, len as usize);
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_file_close(client: *mut AfcWrapper, handle: u64) {
    let c = unsafe { &*client };
    let _ = c.0.file_close(handle);
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_get_file_info(
    client: *mut AfcWrapper,
    path: *const c_char,
) -> *mut c_char {
    let c = unsafe { &*client };
    let path = unsafe { CStr::from_ptr(path).to_str().unwrap() };
    match c.0.get_file_info(path) {
        Ok(info) => {
            let pairs: Vec<String> = info
                .iter()
                .map(|(k, v)| format!("\"{}\":\"{}\"", k, v))
                .collect();
            to_char(format!("{{{}}}", pairs.join(",")))
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_read_directory(
    client: *mut AfcWrapper,
    path: *const c_char,
) -> *mut c_char {
    let c = unsafe { &*client };
    let path = unsafe { CStr::from_ptr(path).to_str().unwrap() };
    match c.0.read_directory(path) {
        Ok(entries) => {
            let json_entries: Vec<String> = entries
                .iter()
                .map(|e| format!("\"{}\"", e.replace('"', "\\\"")))
                .collect();
            to_char(format!("[{}]", json_entries.join(",")))
        }
        Err(_) => std::ptr::null_mut(),
    }
}

// --- InstProxy ---
pub struct InstProxyWrapper<'a>(InstProxyClient<'a>);

#[no_mangle]
pub extern "C" fn rust_bridge_instproxy_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut InstProxyWrapper<'static> {
    let d = unsafe { &*device };
    let label = unsafe { CStr::from_ptr(label) }.to_str().unwrap();
    unsafe {
        match d.0.new_instproxy_client(label) {
            Ok(c) => Box::into_raw(Box::new(InstProxyWrapper(std::mem::transmute(c)))),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_instproxy_install(
    client: *mut InstProxyWrapper,
    path: *const c_char,
) -> bool {
    let c = unsafe { &*client };
    let path = unsafe { CStr::from_ptr(path).to_str().unwrap() };
    c.0.install(path, None).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_instproxy_uninstall(
    client: *mut InstProxyWrapper,
    bundle_id: *const c_char,
) -> bool {
    let c = unsafe { &*client };
    let bundle_id = unsafe { CStr::from_ptr(bundle_id).to_str().unwrap() };
    c.0.uninstall(bundle_id, None).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_instproxy_lookup(
    client: *mut InstProxyWrapper,
    app_id: *const c_char,
) -> *mut c_char {
    let c = unsafe { &*client };
    let app_id = unsafe { CStr::from_ptr(app_id).to_str().unwrap() };
    let client_opts = InstProxyClient::create_return_attributes(
        vec![("ApplicationType".to_string(), Plist::new_string("Any"))],
        vec![
            "CFBundleIdentifier".to_string(),
            "CFBundleExecutable".to_string(),
            "CFBundlePath".to_string(),
            "BundlePath".to_string(),
            "Container".to_string(),
        ],
    );
    match c.0.lookup(vec![app_id.to_string()], Some(client_opts)) {
        Ok(result) => match result.dict_get_item(app_id) {
            Ok(app_data) => to_char(app_data.to_string()),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_instproxy_list_apps(
    client: *mut InstProxyWrapper,
) -> *mut c_char {
    let c = unsafe { &*client };
    let client_opts = InstProxyClient::create_return_attributes(
        vec![("ApplicationType".to_string(), Plist::new_string("User"))],
        vec![
            "ApplicationType",
            "CFBundleDisplayName",
            "CFBundleExecutable",
            "CFBundleIdentifier",
            "CFBundleName",
            "CFBundleShortVersionString",
            "CFBundleVersion",
            "Container",
            "Path",
        ],
    );
    match c.0.lookup(vec![], Some(client_opts)) {
        Ok(apps) => to_char(apps.to_string()),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_instproxy_get_path_for_bundle_identifier(
    client: *mut InstProxyWrapper,
    bundle_id: *const c_char,
) -> *mut c_char {
    let c = unsafe { &*client };
    let bundle_id = unsafe { CStr::from_ptr(bundle_id).to_str().unwrap() };
    match c.0.get_path_for_bundle_identifier(bundle_id.to_string()) {
        Ok(path) => to_char(path),
        Err(_) => std::ptr::null_mut(),
    }
}

// --- Misagent ---
pub struct MisagentWrapper<'a>(MisagentClient<'a>);

#[no_mangle]
pub extern "C" fn rust_bridge_misagent_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut MisagentWrapper<'static> {
    let d = unsafe { &*device };
    let label = unsafe { CStr::from_ptr(label) }.to_str().unwrap();
    unsafe {
        match d.0.new_misagent_client(label) {
            Ok(c) => Box::into_raw(Box::new(MisagentWrapper(std::mem::transmute(c)))),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_misagent_install(
    client: *mut MisagentWrapper,
    profile_ptr: *const u8,
    size: u32,
) -> bool {
    let c = unsafe { &*client };
    let data = unsafe { std::slice::from_raw_parts(profile_ptr, size as usize) };
    c.0.install(Plist::new_data(data)).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_misagent_remove(
    client: *mut MisagentWrapper,
    profile_id: *const c_char,
) -> bool {
    let c = unsafe { &*client };
    let profile_id = unsafe { CStr::from_ptr(profile_id).to_str().unwrap() };
    c.0.remove(profile_id.to_string()).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_misagent_copy_all(client: *mut MisagentWrapper) -> *mut c_char {
    let c = unsafe { &*client };
    match c.0.copy(false) {
        Ok(p) => to_char(Plist::from(p).to_string()),
        Err(_) => std::ptr::null_mut(),
    }
}

// --- Debugserver ---
pub struct DebugserverWrapper<'a>(DebugServer<'a>);

#[no_mangle]
pub extern "C" fn rust_bridge_debugserver_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut DebugserverWrapper<'static> {
    let d = unsafe { &*device };
    let _label = unsafe { CStr::from_ptr(label) }.to_str().unwrap();
    unsafe {
        match d.0.new_debug_server("minimuxer") {
            Ok(c) => Box::into_raw(Box::new(DebugserverWrapper(std::mem::transmute(c)))),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_debugserver_send_command(
    client: *mut DebugserverWrapper,
    command: *const c_char,
) -> *mut c_char {
    let c = unsafe { &*client };
    let command = unsafe { CStr::from_ptr(command) }.to_str().unwrap();
    match c.0.send_command(command.to_string().into()) {
        Ok(res) => to_char(format!("{:?}", res)),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_debugserver_set_argv(
    client: *mut DebugserverWrapper,
    argv_json: *const c_char,
) -> bool {
    let c = unsafe { &*client };
    let argv_str = unsafe { CStr::from_ptr(argv_json) }.to_str().unwrap();
    let argv: Vec<String> = match serde_json::from_str(argv_str) {
        Ok(v) => v,
        Err(_) => return false,
    };
    c.0.set_argv(argv).is_ok()
}

// --- MobileImageMounter ---
pub struct MounterWrapper<'a>(MobileImageMounter<'a>);

#[no_mangle]
pub extern "C" fn rust_bridge_mounter_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut MounterWrapper<'static> {
    let d = unsafe { &*device };
    let label = unsafe { CStr::from_ptr(label) }.to_str().unwrap();
    unsafe {
        match d.0.new_mobile_image_mounter(label) {
            Ok(c) => Box::into_raw(Box::new(MounterWrapper(std::mem::transmute(c)))),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_mounter_lookup(
    client: *mut MounterWrapper,
    image_type: *const c_char,
) -> *mut c_char {
    let c = unsafe { &*client };
    let image_type = unsafe { CStr::from_ptr(image_type).to_str().unwrap() };
    match c.0.lookup_image(image_type) {
        Ok(p) => to_char(Plist::from(p).to_string()),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_mounter_upload(
    client: *mut MounterWrapper,
    path: *const c_char,
    signature: *const c_char,
    image_type: *const c_char,
) -> bool {
    let c = unsafe { &*client };
    let path = unsafe { CStr::from_ptr(path).to_str().unwrap() };
    let signature = unsafe { CStr::from_ptr(signature).to_str().unwrap() };
    let image_type = unsafe { CStr::from_ptr(image_type).to_str().unwrap() };
    c.0.upload_image(path, image_type, signature).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_mounter_mount(
    client: *mut MounterWrapper,
    path: *const c_char,
    signature: *const c_char,
    image_type: *const c_char,
) -> bool {
    let c = unsafe { &*client };
    let path = unsafe { CStr::from_ptr(path).to_str().unwrap() };
    let signature = unsafe { CStr::from_ptr(signature).to_str().unwrap() };
    let image_type = unsafe { CStr::from_ptr(image_type).to_str().unwrap() };
    c.0.mount_image(path, image_type, signature).is_ok()
}

// --- Heartbeat ---
pub struct HeartbeatWrapper(HeartbeatClient);

#[no_mangle]
pub extern "C" fn rust_bridge_heartbeat_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut HeartbeatWrapper {
    let d = unsafe { &*device };
    let label = unsafe { CStr::from_ptr(label) }.to_str().unwrap();
    match d.0.new_heartbeat_client(label) {
        Ok(c) => Box::into_raw(Box::new(HeartbeatWrapper(c))),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_heartbeat_receive(
    client: *mut HeartbeatWrapper,
    timeout_ms: u32,
) -> *mut c_char {
    let c = unsafe { &*client };
    match c.0.receive(timeout_ms) {
        Ok(p) => to_char(Plist::from(p).to_string()),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_heartbeat_send(
    client: *mut HeartbeatWrapper,
    plist_xml: *const c_char,
) -> bool {
    let c = unsafe { &*client };
    let xml = unsafe { CStr::from_ptr(plist_xml).to_str().unwrap() };
    let p = match Plist::from_xml(xml.to_string()) {
        Ok(p) => p,
        Err(_) => return false,
    };
    c.0.send(p).is_ok()
}

// --- Utility ---

#[no_mangle]
pub extern "C" fn rust_bridge_set_debug(level: i32) {
    extern "C" {
        fn libusbmuxd_set_debug_level(level: i32);
        fn idevice_set_debug_level(level: i32);
    }
    unsafe {
        libusbmuxd_set_debug_level(level);
        idevice_set_debug_level(level);
    }
}

// --- Post-17 (delegates to post17.rs) ---

#[no_mangle]
pub extern "C" fn rust_bridge_debug_app_post17(
    app_id: *const c_char,
    muxer_addr: *const c_char,
    device_ip: *const c_char,
) -> i32 {
    let app_id = unsafe { CStr::from_ptr(app_id) }
        .to_str()
        .unwrap()
        .to_string();
    let muxer_addr = unsafe { CStr::from_ptr(muxer_addr) }
        .to_str()
        .unwrap()
        .to_string();
    let device_ip = unsafe { CStr::from_ptr(device_ip) }
        .to_str()
        .unwrap()
        .to_string();
    post17::debug_app_post17(app_id, muxer_addr, device_ip)
}

#[no_mangle]
pub extern "C" fn rust_bridge_mount_personalized_ddi(
    image_ptr: *const u8,
    image_len: u32,
    trustcache_ptr: *const u8,
    trustcache_len: u32,
    manifest_ptr: *const u8,
    manifest_len: u32,
    muxer_addr: *const c_char,
    device_ip: *const c_char,
) -> i32 {
    let image = unsafe { std::slice::from_raw_parts(image_ptr, image_len as usize) };
    let trustcache = unsafe { std::slice::from_raw_parts(trustcache_ptr, trustcache_len as usize) };
    let manifest = unsafe { std::slice::from_raw_parts(manifest_ptr, manifest_len as usize) };
    let muxer_addr = unsafe { CStr::from_ptr(muxer_addr) }
        .to_str()
        .unwrap()
        .to_string();
    let device_ip = unsafe { CStr::from_ptr(device_ip) }
        .to_str()
        .unwrap()
        .to_string();
    post17::mount_personalized_ddi(image, trustcache, manifest, muxer_addr, device_ip)
}
