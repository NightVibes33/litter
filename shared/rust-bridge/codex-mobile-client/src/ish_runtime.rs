//! iOS-only iSH bootstrap + run surface. Port of the former Obj-C
//! `apps/ios/Sources/Litter/Bridge/IshBridge.{h,m}` into Rust.
//!
//! Responsibilities, mirroring the Obj-C original 1:1:
//! 1. Extract the bundled `fs` rootfs into `<app_support>/fs/` on first launch.
//! 2. `chmod 0644` the fakefs `meta.db` so SQLite can write.
//! 3. Boot the iSH kernel at `<app_support>/fs/data` with `/root` as cwd.
//! 4. Install small runtime directories and pass the iSH environment on every
//!    command (`LANG`, `TMPDIR`, `CODEX_HOME`, …).
//! 5. Snapshot host DNS into `/etc/resolv.conf` inside the fakefs.
//! 6. Mount `<documents>/Apps/` at `/mnt/apps/` via iSH's `realfs` driver.
//! 7. Mount native Codex home at `/mnt/codex` and bridge `/root/.codex`.
//! 8. Register the `codex_core` exec hook (`ish_exec::install()`).
//!
//! After `bootstrap`, `run(cmd, cwd)` dispatches command strings through the
//! persistent `/bin/sh` the same way `codex_ish_run` did in Obj-C.

use std::collections::HashMap;
use std::ffi::{CStr, c_char, c_int, c_uint};
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use ish_embed_host::IshInstance;

use crate::ish_types::IshBootstrapError;

// Numeric error codes preserved for back-compat with the previous `ish` crate
// surface. The Swift side observes these as negative `Int32` values.
pub const ISH_E_BOOT: i32 = -1;
pub const ISH_E_MOUNT: i32 = -2;
pub const ISH_E_EXECVE: i32 = -3;
pub const ISH_E_PIPE: i32 = -4;
pub const ISH_E_THREAD: i32 = -5;
pub const ISH_E_NOT_RUNNING: i32 = -6;
pub const ISH_E_IO: i32 = -7;
pub const ISH_E_TIMEOUT: i32 = -8;
pub const ISH_E_NOMEM: i32 = -9;
pub const ISH_E_ARGS: i32 = -10;
const BOOTSTRAP_COMMAND_TIMEOUT_MS: u64 = 10_000;
const INSTANCE_WAIT_TIMEOUT: Duration = Duration::from_secs(60);
const ROOTFS_STAMP_FILE: &str = ".litter-rootfs-id";
const ROOTFS_ARCH_FILE: &str = "data/etc/apk/arch";
const ROOTFS_ALPINE_RELEASE_FILE: &str = "data/etc/alpine-release";
const ROOTFS_ROOT_HOME_DIR: &str = "data/root";

impl From<ish_embed_host::IshError> for IshBootstrapError {
    fn from(err: ish_embed_host::IshError) -> Self {
        IshBootstrapError::Ish(err.to_string())
    }
}

static INSTANCE: OnceLock<IshInstance> = OnceLock::new();
static READY: OnceLock<()> = OnceLock::new();

pub(crate) fn instance() -> Option<&'static IshInstance> {
    INSTANCE.get()
}

/// Wait up to `timeout` for `bootstrap` to finish on another thread. Returns
/// the live instance once it's published, or `None` if the timeout elapses.
/// Used by the terminal session opener so a UI tap that races the on-launch
/// bootstrap doesn't surface a misleading "iSH has not been bootstrapped"
/// error to the user.
pub(crate) async fn instance_or_wait(timeout: Duration) -> Option<&'static IshInstance> {
    if let Some(instance) = INSTANCE.get() {
        return Some(instance);
    }
    let deadline = Instant::now() + timeout;
    let poll = Duration::from_millis(100);
    while Instant::now() < deadline {
        tokio::time::sleep(poll).await;
        if let Some(instance) = INSTANCE.get() {
            return Some(instance);
        }
    }
    None
}

pub(crate) async fn ready_or_wait(timeout: Duration) -> bool {
    if READY.get().is_some() {
        return true;
    }
    let deadline = Instant::now() + timeout;
    let poll = Duration::from_millis(100);
    while Instant::now() < deadline {
        tokio::time::sleep(poll).await;
        if READY.get().is_some() {
            return true;
        }
    }
    false
}

pub(crate) async fn ready_instance_or_wait(timeout: Duration) -> Option<&'static IshInstance> {
    if ready_or_wait(timeout).await {
        INSTANCE.get()
    } else {
        None
    }
}

fn ready_or_wait_blocking(timeout: Duration) -> bool {
    if READY.get().is_some() {
        return true;
    }
    let deadline = Instant::now() + timeout;
    let poll = Duration::from_millis(100);
    while Instant::now() < deadline {
        std::thread::sleep(poll);
        if READY.get().is_some() {
            return true;
        }
    }
    false
}

fn instance_or_wait_blocking(timeout: Duration) -> Option<&'static IshInstance> {
    if let Some(instance) = INSTANCE.get() {
        return Some(instance);
    }
    let deadline = Instant::now() + timeout;
    let poll = Duration::from_millis(100);
    while Instant::now() < deadline {
        std::thread::sleep(poll);
        if let Some(instance) = INSTANCE.get() {
            return Some(instance);
        }
    }
    None
}

/// One-time iSH boot. Mirrors `codex_ish_init` + the post-init setup calls in
/// IshBridge.m. After this returns `Ok`, `run()` is safe to call and the
/// codex_core exec hook has been installed.
///
/// * `bundle_fs_path` — absolute path to the `fs` directory inside the app
///   bundle (Swift resolves this via `Bundle.main.url(forResource:"fs", …)`).
/// * `application_support_dir` — Application Support dir for the app; the
///   rootfs lives under `<application_support_dir>/fs/`.
/// * `documents_dir` — the app's Documents directory; `Apps/` inside it is
///   bind-mounted at `/mnt/apps` inside the fakefs.
pub fn bootstrap(
    bundle_fs_path: &Path,
    application_support_dir: &Path,
    documents_dir: &Path,
) -> Result<(), IshBootstrapError> {
    if INSTANCE.get().is_some() {
        return Err(IshBootstrapError::AlreadyBootstrapped);
    }

    let dest = application_support_dir.join("fs");
    extract_rootfs_if_needed(bundle_fs_path, &dest)?;
    ensure_root_home(&dest)?;
    sanitize_root_home_volatiles(&dest)?;

    let meta_db = dest.join("meta.db");
    if meta_db.exists() {
        let mut perms = fs::metadata(&meta_db)?.permissions();
        perms.set_mode(0o644);
        if let Err(err) = fs::set_permissions(&meta_db, perms) {
            eprintln!("[ish] chmod 0644 on meta.db failed: {err}");
        }
    }

    let data_path = dest.join("data");
    eprintln!(
        "[ish] booting kernel with rootfs='{}' workdir='/root'",
        data_path.display()
    );
    let instance = IshInstance::boot(&data_path, Some(Path::new("/root")))?;
    eprintln!("[ish] kernel booted");

    INSTANCE
        .set(instance)
        .map_err(|_| IshBootstrapError::AlreadyBootstrapped)?;

    // Now that INSTANCE is published, bootstrap setup can run inside the
    // fakefs. Public command dispatch waits for READY below so normal user
    // commands cannot race this setup window.
    runtime_setup();
    mount_codex_home(application_support_dir);
    write_resolv_conf();
    mount_apps_dir(documents_dir);

    crate::ish_exec::install();
    let _ = READY.set(());

    Ok(())
}

/// Default working directory for iSH-backed local sessions. Port of
/// `codex_ish_default_cwd` — always `/root` (Alpine's root home).
pub fn default_cwd() -> &'static str {
    "/root"
}

/// Diagnostic readiness check. This is available for explicit diagnostics; app launch
/// does not gate startup on it.
pub fn preflight() -> (i32, Vec<u8>) {
    if READY.get().is_none() {
        eprintln!("[ish] preflight called before bootstrap completed");
        return (ISH_E_NOT_RUNNING, b"iSH runtime is not ready\n".to_vec());
    }

    run("true", None, Some(BOOTSTRAP_COMMAND_TIMEOUT_MS))
}

/// Run `cmd` through the persistent `/bin/sh`. When `cwd` is non-empty the
/// command is wrapped as `cd '<cwd>' && <cmd>` (same shell-quote pass as the
/// Obj-C port). Returns (exit_code, merged stdout+stderr bytes). If the kernel
/// has not been booted or the FFI call fails, returns a negative ISH_E_* code
/// and an empty byte vector — matching the IshBridge.m error semantics so the
/// exec-hook path can surface the failure without a nil pointer panic.
pub fn run(cmd: &str, cwd: Option<&str>, timeout_ms: Option<u64>) -> (i32, Vec<u8>) {
    run_streaming(cmd, cwd, timeout_ms, |_| {})
}

pub fn run_streaming<F>(
    cmd: &str,
    cwd: Option<&str>,
    timeout_ms: Option<u64>,
    on_output: F,
) -> (i32, Vec<u8>)
where
    F: FnMut(&[u8]),
{
    run_streaming_inner(cmd, cwd, timeout_ms, true, on_output)
}

fn run_bootstrap_command(cmd: &str, timeout_ms: Option<u64>) -> (i32, Vec<u8>) {
    run_streaming_inner(cmd, None, timeout_ms, false, |_| {})
}

fn run_streaming_inner<F>(
    cmd: &str,
    cwd: Option<&str>,
    timeout_ms: Option<u64>,
    require_ready: bool,
    mut on_output: F,
) -> (i32, Vec<u8>)
where
    F: FnMut(&[u8]),
{
    if require_ready && !ready_or_wait_blocking(INSTANCE_WAIT_TIMEOUT) {
        eprintln!("[ish] run() called before bootstrap completed");
        let output = b"iSH runtime is not ready\n".to_vec();
        on_output(&output);
        return (ISH_E_NOT_RUNNING, output);
    }

    let Some(instance) = instance_or_wait_blocking(INSTANCE_WAIT_TIMEOUT) else {
        eprintln!("[ish] run() called before bootstrap succeeded");
        let output = b"iSH runtime is not bootstrapped\n".to_vec();
        on_output(&output);
        return (ISH_E_NOT_RUNNING, output);
    };

    // A restored session can point at a deleted fakefs directory. Fall back to
    // /root instead of failing basic commands such as `pwd` before they run.
    let wrapped = match cwd {
        Some(c) if !c.is_empty() => format!(
            "if cd {} 2>/dev/null; then {}; else cd {} && {}; fi",
            shell_quote(c),
            cmd,
            shell_quote(default_cwd()),
            cmd
        ),
        _ => cmd.to_string(),
    };

    let argv = ["/bin/sh".to_string(), "-c".to_string(), wrapped];
    let env = runtime_env();
    let cwd_path = PathBuf::from("/");
    instance.run_oneshot_streaming(&argv, &cwd_path, &env, timeout_ms, &mut on_output)
}

// ── post-init setup helpers ──────────────────────────────────────────────
// These mirror codex_ish_runtime_setup / codex_ish_write_resolv_conf /
// codex_ish_mount_apps_dir from IshBridge.m. They bypass the public ready
// latch because they are the work that makes the runtime ready.

const RUNTIME_SETUP_SCRIPT: &str = concat!(
    "mkdir -p /dev /tmp /var/tmp /usr/local/bin /root/litter ",
    "/root/.litter/buildkit/requests /root/.litter/builds ;",
    "chmod 1777 /tmp /var/tmp 2>/dev/null || true ;",
    "ensure_char_device() { path=\"$1\"; major=\"$2\"; minor=\"$3\"; mode=\"$4\"; ",
    "if [ -c \"$path\" ]; then chmod \"$mode\" \"$path\" || true; return; fi; ",
    "if [ -e \"$path\" ]; then rm -f \"$path\"; fi; ",
    "mknod -m \"$mode\" \"$path\" c \"$major\" \"$minor\" 2>/dev/null || true; };",
    "ensure_char_device /dev/null 1 3 666 ;",
    "ensure_char_device /dev/random 1 8 666 ;",
    "ensure_char_device /dev/urandom 1 9 666",
);

pub(crate) fn runtime_env() -> HashMap<String, String> {
    HashMap::from([
        (
            "PATH".to_string(),
            "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin".to_string(),
        ),
        ("HOME".to_string(), "/root".to_string()),
        ("USER".to_string(), "root".to_string()),
        ("LOGNAME".to_string(), "root".to_string()),
        ("LANG".to_string(), "C.UTF-8".to_string()),
        ("LC_ALL".to_string(), "C.UTF-8".to_string()),
        ("TMPDIR".to_string(), "/tmp".to_string()),
        // No tty under the exec hook: force pagers to dump and exit so
        // commands like `git log` do not block waiting for interaction.
        ("PAGER".to_string(), "cat".to_string()),
        ("EDITOR".to_string(), "vi".to_string()),
        ("HOSTNAME".to_string(), "litter".to_string()),
        // This fakefs path is symlinked to the app's native Codex home
        // during bootstrap, so shell-installed skills are visible to Codex.
        ("CODEX_HOME".to_string(), "/root/.codex".to_string()),
    ])
}

fn runtime_setup() {
    let (rc, _) = run_bootstrap_command(RUNTIME_SETUP_SCRIPT, Some(BOOTSTRAP_COMMAND_TIMEOUT_MS));
    if rc != 0 {
        eprintln!("[ish] runtime setup failed rc={rc}");
    }
}

fn mount_codex_home(application_support_dir: &Path) {
    let codex_home = application_support_dir.join("codex");
    if let Err(err) = fs::create_dir_all(codex_home.join("skills")) {
        eprintln!("[ish] could not create {}: {err}", codex_home.display());
        return;
    }
    let Some(codex_home_str) = codex_home.to_str() else {
        eprintln!("[ish] CODEX_HOME dir not utf-8: {}", codex_home.display());
        return;
    };

    let cmd = codex_home_bridge_script(codex_home_str);
    let (rc, output) = run_bootstrap_command(&cmd, Some(BOOTSTRAP_COMMAND_TIMEOUT_MS));
    if rc != 0 {
        let message = String::from_utf8_lossy(&output);
        eprintln!("[ish] mount /root/.codex bridge failed rc={rc}: {message}");
    } else {
        eprintln!("[ish] /root/.codex bridged to '{}'", codex_home_str);
    }
}

fn codex_home_bridge_script(codex_home: &str) -> String {
    format!(
        concat!(
            "mkdir -p /mnt/codex /tmp ;",
            "chmod 1777 /tmp ;",
            "mount -t real {} /mnt/codex || exit $? ;",
            "if [ -L /root/.codex ]; then rm /root/.codex; fi ;",
            "if [ -d /root/.codex ]; then ",
            "cp -a /root/.codex/. /mnt/codex/ 2>/dev/null || true ;",
            "backup=\"/root/.codex.fakefs.$(date +%s)\" ;",
            "mv /root/.codex \"$backup\" 2>/dev/null || rm -rf /root/.codex ;",
            "fi ;",
            "ln -s /mnt/codex /root/.codex ;",
            "mkdir -p /root/.codex/skills ;",
            "chmod 700 /root/.codex"
        ),
        shell_quote(codex_home)
    )
}

fn write_resolv_conf() {
    let body = resolv_conf_body();
    let cmd = format!("printf %s {} > /etc/resolv.conf", shell_quote(&body));
    let (rc, _) = run_bootstrap_command(&cmd, Some(BOOTSTRAP_COMMAND_TIMEOUT_MS));
    if rc != 0 {
        eprintln!("[ish] failed to write /etc/resolv.conf rc={rc}");
    } else {
        eprintln!("[ish] /etc/resolv.conf installed ({} bytes)", body.len());
    }
}

fn mount_apps_dir(documents_dir: &Path) {
    let apps_dir = documents_dir.join("Apps");
    if let Err(err) = fs::create_dir_all(&apps_dir) {
        eprintln!("[ish] could not create {}: {err}", apps_dir.display());
        return;
    }
    let Some(apps_str) = apps_dir.to_str() else {
        eprintln!("[ish] apps dir not utf-8: {}", apps_dir.display());
        return;
    };
    let cmd = format!(
        "mkdir -p /mnt/apps && mount -t real {} /mnt/apps",
        shell_quote(apps_str)
    );
    let (rc, _) = run_bootstrap_command(&cmd, Some(BOOTSTRAP_COMMAND_TIMEOUT_MS));
    if rc != 0 {
        eprintln!("[ish] mount /mnt/apps failed rc={rc}");
    } else {
        eprintln!("[ish] /mnt/apps mounted from '{}'", apps_str);
    }
}

// ── bundled rootfs extraction ────────────────────────────────────────────

fn extract_rootfs_if_needed(source: &Path, dest: &Path) -> Result<(), IshBootstrapError> {
    if !source.is_dir() {
        return Err(IshBootstrapError::BundledRootfsMissing(
            source.display().to_string(),
        ));
    }

    if dest.is_dir() {
        let source_identity = rootfs_identity(source)?;
        let dest_identity = rootfs_identity(dest)?;
        if rootfs_identity_matches(source_identity.as_ref(), dest_identity.as_ref()) {
            return Ok(());
        }
        eprintln!(
            "[ish] rootfs identity changed bundled={} installed={}",
            display_rootfs_identity(source_identity.as_ref()),
            display_rootfs_identity(dest_identity.as_ref())
        );
    }

    if dest.exists() {
        eprintln!(
            "[ish] replacing extracted rootfs at '{}' with bundled rootfs",
            dest.display()
        );
    }
    replace_dir_recursive(source, dest)?;
    Ok(())
}

fn rootfs_identity(root: &Path) -> io::Result<Option<String>> {
    if let Some(stamp) = read_rootfs_stamp(root)? {
        return Ok(Some(format!("stamp:{stamp}")));
    }

    let arch = read_trimmed_file(root.join(ROOTFS_ARCH_FILE))?;
    let alpine_release = read_trimmed_file(root.join(ROOTFS_ALPINE_RELEASE_FILE))?;
    if let Some(arch) = arch.or_else(|| detect_musl_arch(root)) {
        return Ok(Some(format!(
            "arch:{arch};alpine:{}",
            alpine_release.as_deref().unwrap_or("unknown")
        )));
    }

    Ok(None)
}

fn rootfs_identity_matches(source: Option<&String>, dest: Option<&String>) -> bool {
    match source {
        Some(source) => dest.is_some_and(|dest| dest == source),
        None => true,
    }
}

fn display_rootfs_identity(identity: Option<&String>) -> &str {
    identity.map(String::as_str).unwrap_or("unknown")
}

fn read_rootfs_stamp(root: &Path) -> io::Result<Option<String>> {
    read_trimmed_file(root.join(ROOTFS_STAMP_FILE))
}

fn read_trimmed_file(path: impl AsRef<Path>) -> io::Result<Option<String>> {
    match fs::read_to_string(path) {
        Ok(value) => {
            let value = value.trim();
            if value.is_empty() {
                Ok(None)
            } else {
                Ok(Some(value.to_string()))
            }
        }
        Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(err) => Err(err),
    }
}

fn detect_musl_arch(root: &Path) -> Option<String> {
    let entries = fs::read_dir(root.join("data/lib")).ok()?;
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(name) = name.to_str() else {
            continue;
        };
        if name.contains("musl-aarch64") {
            return Some("aarch64".to_string());
        }
        if name.contains("musl-x86") || name.contains("musl-i386") {
            return Some("x86".to_string());
        }
    }
    None
}

fn replace_dir_recursive(src: &Path, dst: &Path) -> io::Result<()> {
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)?;
    }

    let name = dst
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("fs");
    let tmp = dst.with_file_name(format!(".{name}.tmp-{}", std::process::id()));

    remove_path_if_exists(&tmp)?;
    copy_dir_recursive(src, &tmp)?;
    preserve_root_home(dst, &tmp)?;
    remove_path_if_exists(dst)?;
    fs::rename(&tmp, dst)?;
    Ok(())
}

fn preserve_root_home(old_root: &Path, new_root: &Path) -> io::Result<()> {
    let old_home = old_root.join(ROOTFS_ROOT_HOME_DIR);
    let old_meta = match fs::symlink_metadata(&old_home) {
        Ok(meta) => meta,
        Err(err) if err.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(err) => return Err(err),
    };
    if !old_meta.is_dir() {
        return Ok(());
    }

    let new_home = new_root.join(ROOTFS_ROOT_HOME_DIR);
    remove_path_if_exists(&new_home)?;
    if let Some(parent) = new_home.parent() {
        fs::create_dir_all(parent)?;
    }
    copy_dir_recursive(&old_home, &new_home)?;
    quarantine_root_home_volatiles(&new_home)?;
    eprintln!("[ish] preserved /root across rootfs replacement");
    Ok(())
}

fn ensure_root_home(rootfs: &Path) -> io::Result<()> {
    let home = rootfs.join(ROOTFS_ROOT_HOME_DIR);
    if !home.exists() {
        eprintln!("[ish] extracted rootfs was missing /root; creating it before kernel boot");
        fs::create_dir_all(&home)?;
    }
    if home.is_dir() {
        let mut perms = fs::metadata(&home)?.permissions();
        perms.set_mode(0o700);
        if let Err(err) = fs::set_permissions(&home, perms) {
            eprintln!("[ish] chmod 0700 on /root failed: {err}");
        }
    }
    Ok(())
}

fn sanitize_root_home_volatiles(rootfs: &Path) -> io::Result<()> {
    let home = rootfs.join(ROOTFS_ROOT_HOME_DIR);
    if home.is_dir() {
        quarantine_root_home_volatiles(&home)?;
    }
    Ok(())
}

fn quarantine_root_home_volatiles(home: &Path) -> io::Result<()> {
    let quarantine = home.join(".litter").join("preserved-root");
    for volatile in [".litter-buildkit", "builds", "litter"] {
        let path = home.join(volatile);
        if fs::symlink_metadata(&path).is_err() {
            continue;
        }
        fs::create_dir_all(&quarantine)?;
        let mut target = quarantine.join(volatile);
        if target.exists() {
            target = quarantine.join(format!("{}-{}", volatile, std::process::id()));
        }
        if let Err(err) = fs::rename(&path, &target) {
            eprintln!("[ish] failed to quarantine /root/{volatile}: {err}; removing");
            remove_path_if_exists(&path)?;
        } else {
            eprintln!("[ish] quarantined /root/{volatile} before fakefs boot");
        }
    }
    Ok(())
}

fn remove_path_if_exists(path: &Path) -> io::Result<()> {
    match fs::symlink_metadata(path) {
        Ok(meta) if meta.is_dir() => fs::remove_dir_all(path),
        Ok(_) => fs::remove_file(path),
        Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(err),
    }
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ft = entry.file_type()?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        if ft.is_dir() {
            copy_dir_recursive(&src_path, &dst_path)?;
        } else if ft.is_symlink() {
            let target = fs::read_link(&src_path)?;
            // Unix symlink copy; iSH fakefs data dir contains plain files +
            // dirs in practice, but tolerate symlinks in the bundle just in
            // case.
            std::os::unix::fs::symlink(&target, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path)?;
        }
    }
    Ok(())
}

use crate::shell_quoting::posix_quote as shell_quote;

// ── resolv.conf snapshot (libresolv FFI) ─────────────────────────────────
//
// Apple's <resolv.h> macro-renames `res_ninit` / `res_getservers` /
// `res_ndestroy` to `res_9_*`, so libresolv.9.tbd on iPhoneOS.sdk exports
// the `res_9_*` symbols. The Rust FFI declares those names directly.
//
// We reproduce `codex_ish_resolv_conf_body()` from IshBridge.m with one
// intentional scope narrowing: we do not emit the `search …` line. Reading
// `struct __res_state::dnsrch` requires reaching into an opaque Apple
// resolver struct with no stable ABI contract; nameservers alone are enough
// for the bootstrap script to reach apk/curl, which is what the original
// Obj-C path was protecting. Empty search list falls through to the public
// resolver fallback below, matching the Obj-C "empty ⇒ fallback" semantic.

// Size chosen generously: the 64-bit Apple `struct __res_state` layout is
// around 1 KB (see resolv.h:182-232; includes MAXNS=3 sockaddr_in slots,
// MAXDNSRCH+1=7 char* pointers, and a 72-byte `_u` union). 4 KB zeroed is a
// safe upper bound that doesn't depend on Apple's internal offsets staying
// stable across SDKs.
const RES_STATE_BUF: usize = 4096;
// `union res_sockaddr_union` is 128-byte `__space` plus alignment padding
// (resolv.h:242-253). 256 bytes is the safe upper bound.
const RES_SOCKADDR_UNION_BUF: usize = 256;
// `<arpa/nameser.h>` / `<resolv.h>` — maximum name servers res_getservers
// will return.
const MAXNS: c_int = 3;

// `<netdb.h>` on Apple.
const NI_MAXHOST: usize = 1025;
const NI_NUMERICHOST: c_int = 0x0000_0002;

#[repr(C)]
struct Sockaddr {
    sa_len: u8,
    sa_family: u8,
    _opaque: [u8; 254],
}

unsafe extern "C" {
    fn res_9_ninit(state: *mut u8) -> c_int;
    fn res_9_getservers(state: *mut u8, servers: *mut u8, count: c_int) -> c_int;
    fn res_9_ndestroy(state: *mut u8);

    fn getnameinfo(
        sa: *const Sockaddr,
        salen: c_uint,
        host: *mut c_char,
        hostlen: c_uint,
        serv: *mut c_char,
        servlen: c_uint,
        flags: c_int,
    ) -> c_int;
}

fn resolv_conf_body() -> String {
    let mut out = String::new();

    let mut res_state = [0u8; RES_STATE_BUF];
    // SAFETY: res_state is a zeroed byte buffer sized generously above the
    // Apple `__res_state` struct. res_9_ninit writes through the pointer; we
    // never dereference fields on the Rust side. res_9_ndestroy is called
    // unconditionally on the Ok path, balancing res_9_ninit.
    let init_rc = unsafe { res_9_ninit(res_state.as_mut_ptr()) };
    if init_rc == 0 {
        let mut servers = [0u8; RES_SOCKADDR_UNION_BUF * MAXNS as usize];
        let found =
            unsafe { res_9_getservers(res_state.as_mut_ptr(), servers.as_mut_ptr(), MAXNS) };
        for i in 0..found.max(0) {
            // SAFETY: Each sockaddr_union slot is RES_SOCKADDR_UNION_BUF
            // bytes; the first byte is sin_len (Apple BSD sockaddr has
            // sa_len as the first byte). A zero sin_len means the slot was
            // left empty by the resolver — skip it, matching IshBridge.m.
            let slot = unsafe { servers.as_ptr().add(i as usize * RES_SOCKADDR_UNION_BUF) };
            let sa_len = unsafe { *slot };
            if sa_len == 0 {
                continue;
            }
            let mut host_buf = [0i8; NI_MAXHOST];
            let rc = unsafe {
                getnameinfo(
                    slot as *const Sockaddr,
                    sa_len as c_uint,
                    host_buf.as_mut_ptr(),
                    NI_MAXHOST as c_uint,
                    std::ptr::null_mut(),
                    0,
                    NI_NUMERICHOST,
                )
            };
            if rc == 0 {
                // SAFETY: getnameinfo NUL-terminates on success.
                let addr = unsafe { CStr::from_ptr(host_buf.as_ptr()) };
                if let Ok(s) = addr.to_str() {
                    out.push_str("nameserver ");
                    out.push_str(s);
                    out.push('\n');
                }
            }
        }
        unsafe { res_9_ndestroy(res_state.as_mut_ptr()) };
    }

    if !out.contains("nameserver ") {
        // Fallback: public resolvers so apk/curl still work when the host
        // resolver handed back nothing (offline, fresh container, etc.).
        out.push_str("nameserver 1.1.1.1\nnameserver 8.8.8.8\n");
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shell_quote_basic() {
        assert_eq!(shell_quote("x"), "'x'");
    }

    #[test]
    fn shell_quote_with_single_quote() {
        assert_eq!(shell_quote("x's"), "'x'\\''s'");
    }

    #[test]
    fn shell_quote_path_with_spaces() {
        assert_eq!(shell_quote("/var/Documents/Apps"), "'/var/Documents/Apps'");
    }

    #[test]
    fn codex_home_bridge_script_mounts_and_preserves_existing_home() {
        let script = codex_home_bridge_script("/var/mobile/Application Support/codex");

        assert!(script.contains(
            "mount -t real '/var/mobile/Application Support/codex' /mnt/codex"
        ));
        assert!(script.contains("cp -a /root/.codex/. /mnt/codex/"));
        assert!(script.contains("ln -s /mnt/codex /root/.codex"));
        assert!(script.contains("mkdir -p /root/.codex/skills"));
    }
}
