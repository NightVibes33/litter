//! Normalize local iSH shell argv before the local codex shell tool forks/execs.
//!
//! Litter runs local commands inside iSH. This hook preserves shell-wrapper
//! behavior while keeping `/tmp` paths inside the fakefs instead of rewriting
//! them to native app-container paths.

use codex_shell_command::parse_command::extract_shell_command;
/// Normalize argv for the mobile local executor. This is installed as the
/// single preflight hook called by upstream Codex immediately before exec.
pub(crate) fn prepare_mobile_exec_argv(argv: &mut Vec<String>) {
    normalize_shell_invocation(argv);
}

fn normalize_shell_invocation(argv: &mut Vec<String>) {
    let Some((_, script)) = extract_shell_command(argv) else {
        return;
    };
    // Reuse the same shell-wrapper parser used for command display, then run
    // the extracted script through the bundled mobile `sh -c`. iSH's
    // /bin/sh supports `-c` like any POSIX shell.
    *argv = vec!["sh".to_string(), "-c".to_string(), script.to_string()];
}

/// Install the local iSH exec preflight. Safe to call multiple times; the
/// underlying OnceLock accepts only the first registration.
#[cfg(all(target_os = "ios", not(target_abi = "macabi")))]
pub fn install() {
    codex_core::exec::set_mobile_exec_preflight(prepare_mobile_exec_argv);
}
