//! Detect the remote shell (POSIX vs. PowerShell).
//!
//! Shell detection is heuristic: `echo %OS%` returns `Windows_NT` only on
//! cmd.exe, while POSIX shells return the literal `%OS%`. A second probe
//! (`echo $env:OS`) covers OpenSSH-on-Windows configs whose default shell
//! is already PowerShell.

use tracing::info;

use super::{RemoteShell, SshClient, append_bridge_info_log};

impl SshClient {
    pub(crate) async fn detect_remote_shell(&self) -> RemoteShell {
        if let Ok(result) = self.exec("echo %OS%").await {
            let out = result.stdout.trim();
            append_bridge_info_log(&format!(
                "ssh_detect_shell cmd_probe out={:?} exit={}",
                out, result.exit_code
            ));
            if out == "Windows_NT" {
                info!("ssh detect shell result=powershell via=cmd_probe");
                return RemoteShell::PowerShell;
            }
        }
        if let Ok(result) = self.exec("echo $env:OS").await {
            let out = result.stdout.trim();
            append_bridge_info_log(&format!(
                "ssh_detect_shell ps_probe out={:?} exit={}",
                out, result.exit_code
            ));
            if out.contains("Windows") {
                info!("ssh detect shell result=powershell via=ps_probe");
                return RemoteShell::PowerShell;
            }
        }
        append_bridge_info_log("ssh_detect_shell result=Posix");
        info!("ssh detect shell result=posix");
        RemoteShell::Posix
    }
}
