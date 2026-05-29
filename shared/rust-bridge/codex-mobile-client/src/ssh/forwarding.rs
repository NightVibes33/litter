//! Local↔remote TCP and Unix-socket plumbing on top of an open SSH session:
//!
//! - `forward_port` / `forward_port_to` / `ensure_forward_port_to` —
//!   bind a local TCP listener, accept connections, open a
//!   `direct-tcpip` channel to the remote, and proxy bytes via
//!   [`port_forward::proxy_connection`].
//! - `abort_forward_port` — abort a previously-started forward.
//! - `open_app_server_proxy_stream` — exec `codex app-server proxy` on the
//!   remote host and expose its stdin/stdout as a bidirectional async stream.

use std::sync::Arc;

use tokio::io::AsyncReadExt;
use tokio::net::TcpListener;
use tracing::{debug, error, info, warn};

use crate::shell_quoting::{cmd_quote, posix_quote as shell_quote};

use super::{
    ForwardTask, RemoteShell, SshClient, SshError, SshExecIo, append_android_debug_log,
    build_posix_exec_command, port_forward::proxy_connection,
};

impl SshClient {
    /// Set up local-to-remote TCP port forwarding.
    ///
    /// Binds a local TCP listener on `local_port` (use 0 for a random port)
    /// and forwards each accepted connection through the SSH tunnel to
    /// `127.0.0.1:remote_port` on the remote host.
    ///
    /// Returns the actual local port that was bound. Forwarding runs in
    /// background tokio tasks until [`Self::disconnect`] is called.
    pub async fn forward_port(&self, local_port: u16, remote_port: u16) -> Result<u16, SshError> {
        self.forward_port_to(local_port, "127.0.0.1", remote_port)
            .await
    }

    /// Set up local-to-remote TCP port forwarding to an explicit remote host.
    pub async fn forward_port_to(
        &self,
        local_port: u16,
        remote_host: &str,
        remote_port: u16,
    ) -> Result<u16, SshError> {
        let (actual_port, task) = self
            .spawn_forward_port(local_port, remote_host, remote_port)
            .await?;
        self.forward_tasks.lock().await.insert(
            actual_port,
            ForwardTask {
                remote_host: remote_host.to_string(),
                remote_port,
                task,
            },
        );
        Ok(actual_port)
    }

    pub async fn ensure_forward_port_to(
        &self,
        local_port: u16,
        remote_host: &str,
        remote_port: u16,
    ) -> Result<u16, SshError> {
        {
            let tasks = self.forward_tasks.lock().await;
            if let Some(existing) = tasks.get(&local_port) {
                if existing.remote_host == remote_host && existing.remote_port == remote_port {
                    return Ok(local_port);
                }
                return Err(SshError::PortForwardFailed(format!(
                    "port {local_port} already forwarded to {}:{}",
                    existing.remote_host, existing.remote_port
                )));
            }
        }
        self.forward_port_to(local_port, remote_host, remote_port)
            .await
    }

    pub async fn abort_forward_port(&self, local_port: u16) -> bool {
        let mut tasks = self.forward_tasks.lock().await;
        if let Some(existing) = tasks.remove(&local_port) {
            existing.task.abort();
            true
        } else {
            false
        }
    }

    async fn spawn_forward_port(
        &self,
        local_port: u16,
        remote_host: &str,
        remote_port: u16,
    ) -> Result<(u16, tokio::task::JoinHandle<()>), SshError> {
        let listener = TcpListener::bind(format!("127.0.0.1:{local_port}"))
            .await
            .map_err(|e| SshError::PortForwardFailed(format!("bind: {e}")))?;

        let actual_port = listener
            .local_addr()
            .map_err(|e| SshError::PortForwardFailed(format!("local_addr: {e}")))?
            .port();

        info!("port forward: 127.0.0.1:{actual_port} -> remote {remote_host}:{remote_port}");

        let handle = Arc::clone(&self.handle);
        let remote_host = remote_host.to_string();

        let task = tokio::spawn(async move {
            loop {
                let (local_stream, peer_addr) = match listener.accept().await {
                    Ok(v) => v,
                    Err(e) => {
                        warn!("port forward accept error: {e}");
                        append_android_debug_log(&format!(
                            "ssh_forward_accept_error listen=127.0.0.1:{} remote={}:{} error={}",
                            actual_port, remote_host, remote_port, e
                        ));
                        break;
                    }
                };

                debug!("port forward: accepted connection from {peer_addr}");
                append_android_debug_log(&format!(
                    "ssh_forward_accept listen=127.0.0.1:{} remote={}:{} peer={}",
                    actual_port, remote_host, remote_port, peer_addr
                ));

                let handle = Arc::clone(&handle);
                let remote_host = remote_host.clone();

                tokio::spawn(async move {
                    let ssh_channel = {
                        let h = handle.lock().await;
                        match h
                            .channel_open_direct_tcpip(
                                &remote_host,
                                remote_port as u32,
                                "127.0.0.1",
                                actual_port as u32,
                            )
                            .await
                        {
                            Ok(ch) => ch,
                            Err(e) => {
                                error!("port forward: open direct-tcpip failed: {e}");
                                append_android_debug_log(&format!(
                                    "ssh_forward_direct_tcpip_failed listen=127.0.0.1:{} remote={}:{} peer={} error={}",
                                    actual_port, remote_host, remote_port, peer_addr, e
                                ));
                                return;
                            }
                        }
                    };

                    append_android_debug_log(&format!(
                        "ssh_forward_direct_tcpip_opened listen=127.0.0.1:{} remote={}:{} peer={}",
                        actual_port, remote_host, remote_port, peer_addr
                    ));

                    if let Err(e) = proxy_connection(
                        local_stream,
                        ssh_channel,
                        actual_port,
                        &remote_host,
                        remote_port,
                        peer_addr,
                    )
                    .await
                    {
                        debug!("port forward proxy ended: {e}");
                        append_android_debug_log(&format!(
                            "ssh_forward_proxy_error listen=127.0.0.1:{} remote={}:{} peer={} error={}",
                            actual_port, remote_host, remote_port, peer_addr, e
                        ));
                    }
                });
            }
        });

        Ok((actual_port, task))
    }

    /// Open Codex's app-server proxy over SSH exec.
    ///
    /// The remote `codex app-server proxy` process speaks the same WebSocket
    /// byte stream that `RemoteAppServerClient::connect_websocket_stream`
    /// expects, so callers can avoid allocating a local TCP listener.
    pub(crate) async fn open_app_server_proxy_stream(
        &self,
        codex_path: &str,
        shell: RemoteShell,
        socket_path: Option<&str>,
    ) -> Result<SshExecIo, SshError> {
        let command = match shell {
            RemoteShell::Posix => {
                let mut command = format!("exec {} app-server proxy", shell_quote(codex_path));
                if let Some(socket_path) = socket_path {
                    command.push_str(&format!(" --sock {}", shell_quote(socket_path)));
                }
                build_posix_exec_command(&command)
            }
            RemoteShell::PowerShell => {
                // Keep the proxy byte stream out of PowerShell's object/text
                // pipeline. `cmd.exe /c` preserves the child process stdio as
                // raw bytes, which the WebSocket stream requires.
                let mut inner = format!(r#""{}" app-server proxy"#, cmd_quote(codex_path));
                if let Some(socket_path) = socket_path {
                    inner.push_str(&format!(r#" --sock "{}""#, cmd_quote(socket_path)));
                }
                format!(r#"cmd.exe /d /c "{inner}""#)
            }
        };

        let mut child = self.open_exec_child(&command).await?;
        let stdin = child.take_stdin().ok_or_else(|| {
            SshError::ConnectionFailed("app-server proxy exec missing stdin".to_string())
        })?;
        let stdout = child.take_stdout().ok_or_else(|| {
            SshError::ConnectionFailed("app-server proxy exec missing stdout".to_string())
        })?;
        let stderr = child.take_stderr();
        let remote_label = socket_path
            .map(|socket_path| format!("app-server-proxy:{socket_path}"))
            .unwrap_or_else(|| "app-server-proxy:default".to_string());

        tokio::spawn(async move {
            let Some(mut stderr) = stderr else {
                return;
            };
            let mut buf = vec![0u8; 4096];
            loop {
                match stderr.read(&mut buf).await {
                    Ok(0) => break,
                    Ok(n) => {
                        let text = String::from_utf8_lossy(&buf[..n]);
                        for line in text.lines().filter(|line| !line.trim().is_empty()) {
                            append_android_debug_log(&format!(
                                "ssh_app_server_proxy_stderr remote={} line={}",
                                remote_label, line
                            ));
                        }
                    }
                    Err(error) => {
                        append_android_debug_log(&format!(
                            "ssh_app_server_proxy_stderr_error remote={} error={}",
                            remote_label, error
                        ));
                        break;
                    }
                }
            }
        });

        Ok(SshExecIo::new(stdout, stdin))
    }
}
