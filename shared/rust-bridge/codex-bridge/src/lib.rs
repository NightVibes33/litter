use std::fs;
use std::os::raw::c_char;
use std::path::PathBuf;

#[cfg(target_os = "ios")]
mod ios_exec;
pub mod voice_handoff;

#[cfg(target_os = "android")]
mod android_jni;

// ===========================================================================
// Platform initialization (called by UniFFI scaffolding on first use)
// ===========================================================================

/// Ensure CODEX_HOME is set to a writable directory.
/// Called early in app lifecycle before any Rust client code runs.
#[unsafe(no_mangle)]
pub extern "C" fn codex_bridge_init() {
    init_codex_home();
    #[cfg(target_os = "ios")]
    init_tls_roots();
    #[cfg(target_os = "ios")]
    {
        ios_exec::init();
        codex_core::exec::set_ios_exec_hook(ios_exec::run_command);
    }
}

fn init_codex_home() {
    let mut candidates: Vec<PathBuf> = Vec::new();

    if let Ok(existing) = std::env::var("CODEX_HOME") {
        candidates.push(PathBuf::from(existing));
    }

    if let Ok(home) = std::env::var("HOME") {
        let home = PathBuf::from(home);
        #[cfg(target_os = "ios")]
        {
            candidates.push(
                home.join("Library")
                    .join("Application Support")
                    .join("codex"),
            );
            candidates.push(home.join("Documents").join(".codex"));
        }
        candidates.push(home.join(".codex"));
    }

    if let Ok(tmpdir) = std::env::var("TMPDIR") {
        candidates.push(PathBuf::from(tmpdir).join("codex-home"));
    }

    for codex_home in candidates {
        match fs::create_dir_all(&codex_home) {
            Ok(()) => {
                unsafe {
                    std::env::set_var("CODEX_HOME", &codex_home);
                }
                eprintln!("[codex-bridge] CODEX_HOME={}", codex_home.display());
                return;
            }
            Err(err) => {
                eprintln!(
                    "[codex-bridge] failed to create CODEX_HOME candidate {:?}: {err}",
                    codex_home
                );
            }
        }
    }

    eprintln!("[codex-bridge] unable to initialize any writable CODEX_HOME location");
}

#[cfg(any(target_os = "ios", target_os = "android"))]
pub(crate) fn init_tls_roots() {
    if let Some(existing) = std::env::var_os("SSL_CERT_FILE") {
        let existing_path = PathBuf::from(existing);
        if existing_path.is_file() {
            return;
        }
        eprintln!(
            "[codex-bridge] replacing stale SSL_CERT_FILE {}",
            existing_path.display()
        );
    }

    let codex_home = match std::env::var("CODEX_HOME") {
        Ok(h) => PathBuf::from(h),
        Err(_) => return,
    };
    let pem_path = codex_home.join("cacert.pem");
    if !pem_path.exists() {
        static CACERT_PEM: &[u8] = include_bytes!("cacert.pem");
        if let Err(e) = fs::write(&pem_path, CACERT_PEM) {
            eprintln!("[codex-bridge] failed to write cacert.pem: {e}");
            return;
        }
    }
    unsafe {
        std::env::set_var("SSL_CERT_FILE", &pem_path);
    }
    eprintln!("[codex-bridge] SSL_CERT_FILE={}", pem_path.display());
}

// ===========================================================================
// Conversation hydration FFI (used by both platforms for standalone hydration)
// ===========================================================================

use codex_app_server_protocol::Turn;
use codex_mobile_client::conversation::{HydrationOptions, hydrate_turns};

#[unsafe(no_mangle)]
pub extern "C" fn codex_hydrate_turns(
    turns_json: *const c_char,
    turns_json_len: usize,
    out_len: *mut usize,
) -> *mut c_char {
    if turns_json.is_null() || out_len.is_null() {
        return std::ptr::null_mut();
    }

    let json_bytes = unsafe { std::slice::from_raw_parts(turns_json as *const u8, turns_json_len) };
    let json_str = match std::str::from_utf8(json_bytes) {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let turns: Vec<Turn> = match serde_json::from_str(json_str) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("[codex-bridge] codex_hydrate_turns: failed to parse turns: {e}");
            return std::ptr::null_mut();
        }
    };

    let items = hydrate_turns(&turns, &HydrationOptions::default());

    let result_json = match serde_json::to_string(&items) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[codex-bridge] codex_hydrate_turns: failed to serialize: {e}");
            return std::ptr::null_mut();
        }
    };

    unsafe {
        *out_len = result_json.len();
    }

    let c_string = match std::ffi::CString::new(result_json) {
        Ok(cs) => cs,
        Err(_) => return std::ptr::null_mut(),
    };
    c_string.into_raw()
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = std::ffi::CString::from_raw(ptr);
        }
    }
}
