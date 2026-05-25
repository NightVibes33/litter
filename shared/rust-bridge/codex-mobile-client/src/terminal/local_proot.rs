#[cfg(target_os = "android")]
mod imp {
    use std::collections::HashMap;
    use std::io::Read;
    use std::path::PathBuf;
    use std::sync::Arc;

    use async_trait::async_trait;
    use tokio::sync::mpsc;

    use super::super::backend::{OpenBackendResult, TerminalBackend, TerminalBackendEvent};
    use super::super::session::{TerminalError, TerminalSize};
    use crate::proot_runtime::{ProotPty, ProotRuntimeError};

    const OUTPUT_CHUNK: usize = 16 * 1024;

    pub(crate) async fn open(
        cwd: Option<String>,
        size: TerminalSize,
    ) -> Result<OpenBackendResult, TerminalError> {
        let instance = crate::proot_runtime::instance().ok_or_else(|| TerminalError::Backend {
            detail: "Android proot has not been bootstrapped".to_string(),
        })?;

        let cwd = PathBuf::from(cwd.unwrap_or_else(default_cwd));
        let mut env = HashMap::new();
        env.insert("TERM".to_string(), "xterm-256color".to_string());
        env.insert("COLORTERM".to_string(), "truecolor".to_string());
        env.insert("HOME".to_string(), "/root".to_string());
        env.insert(
            "PATH".to_string(),
            "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin".to_string(),
        );

        let argv = vec!["/bin/sh".to_string(), "-i".to_string()];
        let spawned = tokio::task::spawn_blocking({
            let instance = Arc::clone(instance);
            move || instance.spawn_pty(&argv, &env, &cwd, size.cols, size.rows)
        })
        .await
        .map_err(|error| TerminalError::Backend {
            detail: format!("joining proot spawn task: {error}"),
        })?
        .map_err(map_error)?;

        let (output_tx, output_rx) = mpsc::channel(256);
        spawn_reader(spawned.reader, output_tx.clone());
        spawn_waiter(spawned.child, output_tx);

        Ok((Arc::new(LocalProotBackend { pty: spawned.pty }), output_rx))
    }

    struct LocalProotBackend {
        pty: Arc<ProotPty>,
    }

    #[async_trait]
    impl TerminalBackend for LocalProotBackend {
        async fn write(&self, data: &[u8]) -> Result<(), TerminalError> {
            let pty = Arc::clone(&self.pty);
            let data = data.to_vec();
            tokio::task::spawn_blocking(move || pty.write(&data))
                .await
                .map_err(|error| TerminalError::Backend {
                    detail: format!("joining proot write task: {error}"),
                })?
                .map_err(map_error)
        }

        async fn resize(&self, size: TerminalSize) -> Result<(), TerminalError> {
            let pty = Arc::clone(&self.pty);
            tokio::task::spawn_blocking(move || pty.resize(size.cols, size.rows))
                .await
                .map_err(|error| TerminalError::Backend {
                    detail: format!("joining proot resize task: {error}"),
                })?
                .map_err(map_error)
        }

        async fn close(&self) -> Result<(), TerminalError> {
            let pty = Arc::clone(&self.pty);
            tokio::task::spawn_blocking(move || pty.kill())
                .await
                .map_err(|error| TerminalError::Backend {
                    detail: format!("joining proot close task: {error}"),
                })?
                .map_err(map_error)
        }
    }

    fn spawn_reader(
        mut reader: Box<dyn Read + Send>,
        output_tx: mpsc::Sender<TerminalBackendEvent>,
    ) {
        std::thread::Builder::new()
            .name("litter-proot-terminal-reader".to_string())
            .spawn(move || {
                let mut buf = vec![0u8; OUTPUT_CHUNK];
                loop {
                    match reader.read(&mut buf) {
                        Ok(0) => break,
                        Ok(n) => {
                            if output_tx
                                .blocking_send(TerminalBackendEvent::Bytes(buf[..n].to_vec()))
                                .is_err()
                            {
                                break;
                            }
                        }
                        Err(error) if error.kind() == std::io::ErrorKind::Interrupted => {}
                        Err(error) => {
                            let _ = output_tx.blocking_send(TerminalBackendEvent::Bytes(
                                format!("\r\n[proot] read error: {error}\r\n").into_bytes(),
                            ));
                            break;
                        }
                    }
                }
            })
            .expect("spawn proot reader thread");
    }

    fn spawn_waiter(
        mut child: Box<dyn portable_pty::Child + Send + Sync>,
        output_tx: mpsc::Sender<TerminalBackendEvent>,
    ) {
        std::thread::Builder::new()
            .name("litter-proot-terminal-waiter".to_string())
            .spawn(move || {
                let code = match child.wait() {
                    Ok(status) => status.exit_code() as i32,
                    Err(error) => {
                        let _ = output_tx.blocking_send(TerminalBackendEvent::Bytes(
                            format!("\r\n[proot] wait error: {error}\r\n").into_bytes(),
                        ));
                        -1
                    }
                };
                let _ = output_tx.blocking_send(TerminalBackendEvent::Exit(code));
            })
            .expect("spawn proot waiter thread");
    }

    fn map_error(error: ProotRuntimeError) -> TerminalError {
        match error {
            ProotRuntimeError::PtraceDenied { detail } => TerminalError::Backend {
                detail: format!(
                    "this Android environment blocks ptrace; use remote shell instead: {detail}"
                ),
            },
            other => TerminalError::Backend {
                detail: format!("{other}"),
            },
        }
    }

    fn default_cwd() -> String {
        "/root".to_string()
    }
}

#[cfg(target_os = "android")]
pub(crate) use imp::open;

#[cfg(not(target_os = "android"))]
pub(crate) async fn open(
    _cwd: Option<String>,
    _size: super::session::TerminalSize,
) -> Result<super::backend::OpenBackendResult, super::session::TerminalError> {
    Err(super::session::TerminalError::Unsupported {
        detail: "local Alpine terminal backend is only available on Android".to_string(),
    })
}
