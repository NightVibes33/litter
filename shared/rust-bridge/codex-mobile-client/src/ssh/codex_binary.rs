//! Locate, launch, and describe a `codex` binary on the remote host.
//!
//! Resolution: `resolve_codex_binary_script_*` produce shell snippets that
//! search the same candidate paths the local resolver uses
//! (`crate::local_server::shell_candidate_lines`), so a remote with the
//! same shape as the user's machine finds the same binary.
//!
//! Launch: `server_launch_command` and `windows_start_process_spec` build
//! the per-shell command pieces that the bootstrap orchestrator stitches
//! together with the nohup / Start-Process wrapper.

use crate::shell_quoting::{cmd_quote, posix_quote as shell_quote, powershell_quote as ps_quote};

use super::{PACKAGE_MANAGER_PROBE, PROFILE_INIT, RemoteShell};

#[derive(Debug, Clone)]
pub(crate) enum RemoteCodexBinary {
    Codex(String),
}

impl RemoteCodexBinary {
    pub(crate) fn path(&self) -> &str {
        match self {
            Self::Codex(path) => path,
        }
    }
}

pub(super) fn resolve_codex_binary_script_posix() -> String {
    // Candidate list is shared with the Rust-native local resolver in
    // `crate::local_server` so the two resolvers cannot drift.
    let shared_lines = crate::local_server::shell_candidate_lines().join("\n");
    crate::ssh_scripts::render(
        crate::ssh_scripts::posix::RESOLVE_CODEX_BINARY,
        &[
            ("PROFILE_INIT", PROFILE_INIT),
            ("PACKAGE_MANAGER_PROBE", PACKAGE_MANAGER_PROBE),
            ("SHARED_LINES", &shared_lines),
        ],
    )
}

pub(super) fn resolve_codex_binary_script_powershell() -> String {
    crate::ssh_scripts::powershell::RESOLVE_CODEX_BINARY.to_string()
}

/// PowerShell `Start-Process` `-FilePath` and `-ArgumentList` strings.
/// Splits because `.cmd` / `.bat` shims can't be invoked directly with
/// `Start-Process`; they have to go through `cmd.exe /d /c`.
pub(super) fn windows_start_process_spec(
    binary: &RemoteCodexBinary,
    listen_url: &str,
) -> (String, String) {
    let args = match binary {
        RemoteCodexBinary::Codex(_) => vec![
            ps_quote("--enable"),
            ps_quote("goals"),
            ps_quote("app-server"),
            ps_quote("--listen"),
            ps_quote(listen_url),
        ],
    };

    if is_windows_cmd_script(binary.path()) {
        let command = match binary {
            RemoteCodexBinary::Codex(path) => {
                format!(
                    r#""{}" --enable goals app-server --listen {}"#,
                    cmd_quote(path),
                    listen_url
                )
            }
        };
        (
            "$env:ComSpec".to_string(),
            format!("@('/d', '/c', {})", ps_quote(&format!(r#""{command}""#))),
        )
    } else {
        (ps_quote(binary.path()), format!("@({})", args.join(", ")))
    }
}

pub(super) fn server_launch_command(
    binary: &RemoteCodexBinary,
    listen_url: &str,
    shell: RemoteShell,
) -> String {
    match shell {
        RemoteShell::Posix => match binary {
            RemoteCodexBinary::Codex(path) => format!(
                "{} --enable goals app-server --listen {}",
                shell_quote(path),
                shell_quote(listen_url)
            ),
        },
        RemoteShell::PowerShell => match binary {
            RemoteCodexBinary::Codex(path) => format!(
                "{} --enable goals app-server --listen {}",
                ps_quote(path),
                ps_quote(listen_url)
            ),
        },
    }
}

fn is_windows_cmd_script(path: &str) -> bool {
    let lower = path.to_ascii_lowercase();
    lower.ends_with(".cmd") || lower.ends_with(".bat")
}
