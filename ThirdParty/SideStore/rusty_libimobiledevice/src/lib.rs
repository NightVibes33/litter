#[doc = include_str!("../README.md")]
#[allow(clippy::all)]
mod bindings;
/// TODO
pub mod callback;
/// A debug macro used throughout the crate
pub mod connection;
/// A module containing all possible errors produced by the library
pub mod error;
/// Creates connections and manages high level interfaces for iOS devices
pub mod idevice;
/// A bare bones representation of a service running on a device.
/// Useful for services that don't have modules or for running raw commands
pub mod service;
/// A module that contains all abstractions for built-in services
pub mod services;

pub(crate) fn libplist_to_rusty_plist<T: serde::de::DeserializeOwned>(
    plist_ptr: bindings::plist_t,
) -> T {
    let mut plist_data = std::ptr::null_mut();
    let mut plist_size = 0;
    unsafe { bindings::plist_to_xml(plist_ptr, &mut plist_data, &mut plist_size) };
    let plist_data = unsafe {
        std::slice::from_raw_parts(plist_data as *const u8, plist_size.try_into().unwrap())
    };
    plist::from_bytes(plist_data).expect("plist is invalid for rusty plist but not libplist. This should be impossible but given libplist's reputation it might be possible")
}
