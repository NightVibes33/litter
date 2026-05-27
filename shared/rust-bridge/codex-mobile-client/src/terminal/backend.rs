use super::session::{TerminalBackendKind, TerminalError, TerminalSize};
use super::ssh_known_hosts::TerminalSshTrustStore;
use async_trait::async_trait;
use std::sync::Arc;
use tokio::sync::mpsc;

#[derive(Debug)]
#[allow(dead_code)]
pub(crate) enum TerminalBackendEvent {
    Bytes(Vec<u8>),
    Exit(i32),
}

#[async_trait]
pub(crate) trait TerminalBackend: Send + Sync {
    async fn write(&self, data: &[u8]) -> Result<(), TerminalError>;
    async fn resize(&self, size: TerminalSize) -> Result<(), TerminalError>;
    async fn close(&self) -> Result<(), TerminalError>;
}

pub(crate) type OpenBackendResult = (
    Arc<dyn TerminalBackend>,
    mpsc::Receiver<TerminalBackendEvent>,
);

pub(crate) async fn open_backend(
    kind: TerminalBackendKind,
    size: TerminalSize,
    trust_store: Option<Arc<TerminalSshTrustStore>>,
) -> Result<OpenBackendResult, TerminalError> {
    validate_size(size)?;
    match kind {
        TerminalBackendKind::LocalIsh { cwd } => super::local_ish::open(cwd, size).await,
        TerminalBackendKind::RemoteAlleycat {
            node_id,
            token,
            relay,
            shell,
        } => super::remote_alleycat::open(node_id, token, relay, shell, size).await,
        TerminalBackendKind::RemoteSsh {
            host,
            port,
            username,
            auth,
            shell,
            accept_unknown_host,
            cwd,
        } => {
            super::ssh::open(
                host,
                port,
                username,
                auth,
                shell,
                accept_unknown_host,
                cwd,
                size,
                trust_store,
            )
            .await
        }
    }
}

pub(crate) fn validate_size(size: TerminalSize) -> Result<(), TerminalError> {
    if size.cols == 0 || size.rows == 0 {
        return Err(TerminalError::InvalidSize {
            detail: format!(
                "terminal size must be non-zero, got {}x{}",
                size.cols, size.rows
            ),
        });
    }
    Ok(())
}
