//! Open a PTY-backed interactive shell channel over an established
//! [`SshClient`]. Returned to the caller as a raw `russh::Channel` so the
//! caller (currently `crate::terminal::ssh`) owns the channel lifecycle
//! and drives the `wait` / control loop on its own task.

use russh::Channel;
use russh::client::Msg;

use super::{SshClient, SshError, append_bridge_info_log};

impl SshClient {
    /// Open a session channel, request a PTY of the given grid size with the
    /// default `xterm-256color` terminfo, then start either the user's login
    /// shell (via `RequestShell`) or `exec <shell>` (optionally prefixed with
    /// `cd <cwd> &&`) if `shell` is `Some`.
    pub(crate) async fn open_terminal_channel(
        &self,
        cols: u16,
        rows: u16,
        shell: Option<&str>,
        cwd: Option<&str>,
    ) -> Result<Channel<Msg>, SshError> {
        let handle = self.handle.lock().await;
        if handle.is_closed() {
            return Err(SshError::Disconnected);
        }
        let channel = handle
            .channel_open_session()
            .await
            .map_err(|error| SshError::ConnectionFailed(format!("open session: {error}")))?;
        drop(handle);

        channel
            .request_pty(true, "xterm-256color", cols as u32, rows as u32, 0, 0, &[])
            .await
            .map_err(|error| SshError::ConnectionFailed(format!("request pty: {error}")))?;

        match shell {
            None => channel
                .request_shell(true)
                .await
                .map_err(|error| SshError::ConnectionFailed(format!("request shell: {error}")))?,
            Some(shell) => {
                let command = match cwd {
                    Some(dir) if !dir.is_empty() => format!(
                        "cd {} && exec {}",
                        super::shell_quote(dir),
                        super::shell_quote(shell)
                    ),
                    _ => format!("exec {}", super::shell_quote(shell)),
                };
                channel
                    .exec(true, command.as_bytes())
                    .await
                    .map_err(|error| {
                        SshError::ConnectionFailed(format!("exec shell override: {error}"))
                    })?;
            }
        }

        append_bridge_info_log(&format!(
            "ssh_terminal_channel_opened cols={} rows={} shell={}",
            cols,
            rows,
            shell.unwrap_or("<login>")
        ));

        Ok(channel)
    }
}
