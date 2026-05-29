use jni::JNIEnv;
use jni::objects::{JClass, JString};
use jni::sys::jint;

/// Set HOME and CODEX_HOME environment variables from Android.
/// Android doesn't set HOME by default, and Rust needs it for data storage.
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_litter_android_core_bridge_UniffiInit_nativeBridgeInit(
    mut env: JNIEnv,
    _class: JClass,
    home_dir: JString,
    codex_home_dir: JString,
) {
    let home: String = match env.get_string(&home_dir) {
        Ok(s) => s.into(),
        Err(_) => return,
    };
    let codex_home: String = match env.get_string(&codex_home_dir) {
        Ok(s) => s.into(),
        Err(_) => return,
    };

    unsafe {
        std::env::set_var("HOME", &home);
        std::env::set_var("CODEX_HOME", &codex_home);
        // Also set TMPDIR if not already set
        if std::env::var("TMPDIR").is_err() {
            let tmpdir = format!("{}/tmp", home);
            let _ = std::fs::create_dir_all(&tmpdir);
            std::env::set_var("TMPDIR", &tmpdir);
        }
    }
    crate::init_tls_roots();
    eprintln!(
        "[codex-bridge] Android init: HOME={}, CODEX_HOME={}",
        home, codex_home
    );
}

/// Legacy stubs — kept so NativeCodexBridge.kt doesn't crash on load.
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_litter_android_core_bridge_NativeCodexBridge_nativeStartServerPort(
    _env: JNIEnv,
    _class: JClass,
) -> jint {
    -1
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_litter_android_core_bridge_NativeCodexBridge_nativeStopServer(
    _env: JNIEnv,
    _class: JClass,
) {
}
