#[cfg(all(target_os = "ios", not(target_abi = "macabi")))]
mod imp {
    use std::path::PathBuf;
    use std::sync::Arc;
    use std::time::{Duration, Instant};

    use async_trait::async_trait;
    use ish_embed_host::{IshSession, PtySize, SessionEvent, WriteStatus};
    use tokio::sync::{broadcast, mpsc};

    use super::super::backend::{OpenBackendResult, TerminalBackend, TerminalBackendEvent};
    use super::super::session::{TerminalError, TerminalSize};

    const OPEN_TIMEOUT: Duration = Duration::from_secs(5);
    const WRITE_STARTING_TIMEOUT: Duration = Duration::from_secs(2);

    pub(crate) async fn open(
        cwd: Option<String>,
        size: TerminalSize,
    ) -> Result<OpenBackendResult, TerminalError> {
        let instance = crate::ish_runtime::instance_or_wait(Duration::from_secs(60))
            .await
            .ok_or_else(|| TerminalError::Backend {
                detail: "iSH bootstrap did not complete in time. Force-quit the app and relaunch; the first launch can take 10–30s while the rootfs is extracted.".to_string(),
            })?;

        let mut env = crate::ish_runtime::runtime_env();
        env.insert("TERM".to_string(), "xterm-256color".to_string());
        env.insert("COLORTERM".to_string(), "truecolor".to_string());

        let cwd =
            PathBuf::from(cwd.unwrap_or_else(|| crate::ish_runtime::default_cwd().to_string()));
        let argv = vec!["/bin/sh".to_string(), "-i".to_string()];
        let session = instance
            .spawn_pty(&argv, &env, &cwd, PtySize {
                cols: size.cols,
                rows: size.rows,
            })
            .map_err(|error| TerminalError::Backend {
                detail: format!("spawning iSH terminal session: {error}"),
            })?;

        let mut events = session.subscribe();
        wait_until_open(&mut events).await?;

        let (output_tx, output_rx) = mpsc::channel(256);
        tokio::spawn(forward_events(events, output_tx));

        Ok((Arc::new(LocalIshBackend { session }), output_rx))
    }

    struct LocalIshBackend {
        session: Arc<IshSession>,
    }

    #[async_trait]
    impl TerminalBackend for LocalIshBackend {
        async fn write(&self, data: &[u8]) -> Result<(), TerminalError> {
            let deadline = Instant::now() + WRITE_STARTING_TIMEOUT;
            loop {
                let status =
                    self.session
                        .write(data)
                        .await
                        .map_err(|error| TerminalError::Backend {
                            detail: format!("writing to iSH terminal session: {error}"),
                        })?;
                match status {
                    WriteStatus::Accepted => return Ok(()),
                    WriteStatus::Starting if Instant::now() < deadline => {
                        tokio::time::sleep(Duration::from_millis(25)).await;
                    }
                    WriteStatus::Starting => {
                        return Err(TerminalError::Backend {
                            detail: "iSH terminal session did not become writable".to_string(),
                        });
                    }
                    WriteStatus::UnknownSession | WriteStatus::StdinClosed => {
                        return Err(TerminalError::Closed);
                    }
                }
            }
        }

        async fn resize(&self, size: TerminalSize) -> Result<(), TerminalError> {
            self.session
                .resize(size.cols, size.rows)
                .await
                .map_err(|error| TerminalError::Backend {
                    detail: format!("resizing iSH terminal session: {error}"),
                })
        }

        async fn close(&self) -> Result<(), TerminalError> {
            self.session
                .terminate()
                .await
                .map_err(|error| TerminalError::Backend {
                    detail: format!("terminating iSH terminal session: {error}"),
                })
        }
    }

    async fn wait_until_open(
        events: &mut broadcast::Receiver<SessionEvent>,
    ) -> Result<(), TerminalError> {
        loop {
            match tokio::time::timeout(OPEN_TIMEOUT, events.recv()).await {
                Ok(Ok(SessionEvent::Opened { .. })) => return Ok(()),
                Ok(Ok(SessionEvent::Failed { message })) => {
                    return Err(TerminalError::Backend {
                        detail: format!("iSH terminal session failed before opening: {message}"),
                    });
                }
                Ok(Ok(SessionEvent::Exited { exit_code, .. })) => {
                    return Err(TerminalError::Backend {
                        detail: format!(
                            "iSH terminal session exited before opening with code {exit_code}"
                        ),
                    });
                }
                Ok(Ok(SessionEvent::Closed)) => {
                    return Err(TerminalError::Backend {
                        detail: "iSH terminal session closed before opening".to_string(),
                    });
                }
                Ok(Ok(SessionEvent::Output { .. })) => {}
                Ok(Err(broadcast::error::RecvError::Lagged(_))) => {}
                Ok(Err(broadcast::error::RecvError::Closed)) => {
                    return Err(TerminalError::Backend {
                        detail: "iSH terminal event stream closed before opening".to_string(),
                    });
                }
                Err(_) => {
                    return Err(TerminalError::Backend {
                        detail: "timed out waiting for iSH terminal session to open".to_string(),
                    });
                }
            }
        }
    }

    async fn forward_events(
        mut events: broadcast::Receiver<SessionEvent>,
        output_tx: mpsc::Sender<TerminalBackendEvent>,
    ) {
        let mut exit_code = None;
        loop {
            match events.recv().await {
                Ok(SessionEvent::Output { bytes, .. }) => {
                    if output_tx
                        .send(TerminalBackendEvent::Bytes(bytes.to_vec()))
                        .await
                        .is_err()
                    {
                        break;
                    }
                }
                Ok(SessionEvent::Exited {
                    exit_code: code, ..
                }) => {
                    exit_code = Some(code);
                }
                Ok(SessionEvent::Closed) => {
                    let _ = output_tx
                        .send(TerminalBackendEvent::Exit(exit_code.unwrap_or(-1)))
                        .await;
                    break;
                }
                Ok(SessionEvent::Failed { message }) => {
                    let _ = output_tx
                        .send(TerminalBackendEvent::Bytes(
                            format!("\r\n[ish] {message}\r\n").into_bytes(),
                        ))
                        .await;
                    let _ = output_tx.send(TerminalBackendEvent::Exit(-1)).await;
                    break;
                }
                Ok(SessionEvent::Opened { .. }) => {}
                Err(broadcast::error::RecvError::Lagged(_)) => {}
                Err(broadcast::error::RecvError::Closed) => {
                    let _ = output_tx
                        .send(TerminalBackendEvent::Exit(exit_code.unwrap_or(-1)))
                        .await;
                    break;
                }
            }
        }
    }
}

#[cfg(all(target_os = "ios", not(target_abi = "macabi")))]
pub(crate) use imp::open;

#[cfg(not(all(target_os = "ios", not(target_abi = "macabi"))))]
pub(crate) async fn open(
    _cwd: Option<String>,
    _size: super::session::TerminalSize,
) -> Result<super::backend::OpenBackendResult, super::session::TerminalError> {
    Err(super::session::TerminalError::Unsupported {
        detail: "local iSH terminal backend is only available on iOS".to_string(),
    })
}
