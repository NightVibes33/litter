use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use crate::idevice_support::mounter::mount_personalized_ddi_rppairing;
use crate::idevice_support::rsd::set_rppairing_file;
use crate::idevice_support::{
    device::{fetch_udid_rppairing, test_device_connection},
    install::{install_ipa_rppairing, remove_app_rppairing, yeet_app_afc_rppairing},
    jit::{debug_app_rppairing, debug_process_rppairing},
    provision::{
        dump_provisioning_profile_rppairing, install_provisioning_profile_rppairing,
        remove_provisioning_profile_rppairing,
    },
};
use crate::IdeviceFfiError;
use crate::post17::RUNTIME;

fn to_char(value: String) -> *mut c_char {
    CString::new(value).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_test_device_connection() -> bool {
    test_device_connection()
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_fetch_udid(
    udid_out: *mut *mut c_char,
) -> *mut IdeviceFfiError {
    if udid_out.is_null() {
        return crate::ffi_err!(idevice::IdeviceError::InvalidArgument);
    }

    unsafe {
        *udid_out = std::ptr::null_mut();
    }

    match RUNTIME.block_on(fetch_udid_rppairing()) {
        Ok(udid) => {
            unsafe {
                *udid_out = to_char(udid);
            }
            std::ptr::null_mut()
        }
        Err(err) => crate::ffi_err!(err),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_yeet_app_afc(
    bundle_id: *const c_char,
    ipa_ptr: *const u8,
    ipa_len: u32,
) -> *mut IdeviceFfiError {
    let bundle_id = unsafe { CStr::from_ptr(bundle_id) }
        .to_str()
        .unwrap()
        .to_string();
    let ipa_bytes = unsafe { std::slice::from_raw_parts(ipa_ptr, ipa_len as usize) };

    RUNTIME.block_on(async move {
        match yeet_app_afc_rppairing(bundle_id, ipa_bytes).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_install_ipa(
    bundle_id: *const c_char,
) -> *mut IdeviceFfiError {
    let bundle_id = unsafe { CStr::from_ptr(bundle_id) }
        .to_str()
        .unwrap()
        .to_string();
    RUNTIME.block_on(async move {
        match install_ipa_rppairing(bundle_id).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_remove_app(bundle_id: *const c_char) -> *mut IdeviceFfiError {
    let bundle_id = unsafe { CStr::from_ptr(bundle_id) }
        .to_str()
        .unwrap()
        .to_string();
    RUNTIME.block_on(async move {
        match remove_app_rppairing(bundle_id).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_debug_app(app_id: *const c_char) -> *mut IdeviceFfiError {
    let app_id = unsafe { CStr::from_ptr(app_id) }
        .to_str()
        .unwrap()
        .to_string();
    RUNTIME.block_on(async move {
        match debug_app_rppairing(app_id).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_debug_process(pid: u32) -> *mut IdeviceFfiError {
    RUNTIME.block_on(async move {
        match debug_process_rppairing(pid).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_install_provisioning_profile(
    profile_ptr: *const u8,
    profile_len: u32,
) -> *mut IdeviceFfiError {
    let profile = unsafe { std::slice::from_raw_parts(profile_ptr, profile_len as usize) };
    RUNTIME.block_on(async move {
        match install_provisioning_profile_rppairing(profile).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_remove_provisioning_profile(
    id: *const c_char,
) -> *mut IdeviceFfiError {
    let id = unsafe { CStr::from_ptr(id) }.to_str().unwrap().to_string();
    RUNTIME.block_on(async move {
        match remove_provisioning_profile_rppairing(id).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_dump_provisioning_profile(
    docs_path: *const c_char,
) -> *mut IdeviceFfiError {
    let docs_path = unsafe { CStr::from_ptr(docs_path) }
        .to_str()
        .unwrap()
        .to_string();
    RUNTIME.block_on(async move {
        match dump_provisioning_profile_rppairing(docs_path).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_set_rppairing_file(
    pairing_file: *const c_char,
) -> *mut IdeviceFfiError {
    let pairing_file_str = unsafe { CStr::from_ptr(pairing_file) }
        .to_str()
        .unwrap()
        .to_string();

    match set_rppairing_file(pairing_file_str) {
        Ok(()) => std::ptr::null_mut(),
        Err(err) => crate::ffi_err!(err),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_mount_personalized_ddi(
    image_ptr: *const u8,
    image_len: u32,
    trustcache_ptr: *const u8,
    trustcache_len: u32,
    manifest_ptr: *const u8,
    manifest_len: u32,
) -> i32 {
    let image = unsafe { std::slice::from_raw_parts(image_ptr, image_len as usize) };
    let trustcache = unsafe { std::slice::from_raw_parts(trustcache_ptr, trustcache_len as usize) };
    let manifest = unsafe { std::slice::from_raw_parts(manifest_ptr, manifest_len as usize) };
    RUNTIME.block_on(async move {
        mount_personalized_ddi_rppairing(image, trustcache, manifest).await
    })
}
