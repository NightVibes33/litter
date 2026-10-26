//! Attachment bytes belong on the connected SSH computer, never at an iOS URL.
use super::ssh::{ManagedSshSession, SshBridge};
use crate::ffi::ClientError;
use crate::ssh::attachment::{begin_script, cancel_script, verify_script};
use base64::Engine;

const MAX_CHUNK_BYTES: usize = 128 * 1024;

impl SshBridge {
    fn attachment_session(
        &self,
        session_id: &str,
        path: Option<&str>,
    ) -> Result<ManagedSshSession, ClientError> {
        if let Some(path) = path {
            let registered = self
                .ssh_attachments
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if !registered.contains(&(session_id.to_string(), path.to_string())) {
                return Err(ClientError::InvalidParams(
                    "Attachment does not belong to this SSH session".into(),
                ));
            }
        }
        self.ssh_sessions
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .get(session_id)
            .cloned()
            .ok_or_else(|| ClientError::InvalidParams("SSH session is no longer connected".into()))
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl SshBridge {
    pub async fn ssh_attachment_begin(
        &self,
        session_id: String,
        name: String,
    ) -> Result<String, ClientError> {
        let session = self.attachment_session(&session_id, None)?;
        let script = begin_script(session.shell, &uuid::Uuid::new_v4().to_string(), &name);
        let result = session
            .client
            .exec_shell(&script, session.shell)
            .await
            .map_err(|error| ClientError::Transport(error.to_string()))?;
        let path = result.stdout.trim().to_string();
        if result.exit_code != 0 || path.is_empty() || path.contains(['\n', '\r', '\0']) {
            return Err(ClientError::Transport(
                "Could not create an attachment on the SSH computer".into(),
            ));
        }
        self.ssh_attachments
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .insert((session_id, path.clone()));
        Ok(path)
    }

    pub async fn ssh_attachment_append(
        &self,
        session_id: String,
        remote_path: String,
        content_base64: String,
    ) -> Result<(), ClientError> {
        let session = self.attachment_session(&session_id, Some(&remote_path))?;
        if content_base64.len() > MAX_CHUNK_BYTES.div_ceil(3) * 4 {
            return Err(ClientError::InvalidParams(
                "Attachment chunk is too large".into(),
            ));
        }
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(content_base64)
            .map_err(|_| ClientError::InvalidParams("Invalid attachment bytes".into()))?;
        if bytes.is_empty() || bytes.len() > MAX_CHUNK_BYTES {
            return Err(ClientError::InvalidParams(
                "Attachment chunk is empty or too large".into(),
            ));
        }
        tokio::time::timeout(
            std::time::Duration::from_secs(30),
            session
                .client
                .append_upload(&bytes, &remote_path, session.shell),
        )
        .await
        .map_err(|_| ClientError::Transport("Attachment upload timed out".into()))?
        .map_err(|error| ClientError::Transport(error.to_string()))
    }

    pub async fn ssh_attachment_verify(
        &self,
        session_id: String,
        remote_path: String,
        expected_size: u64,
    ) -> Result<(), ClientError> {
        if expected_size == 0 {
            return Err(ClientError::InvalidParams("Attachment is empty".into()));
        }
        let session = self.attachment_session(&session_id, Some(&remote_path))?;
        let result = session
            .client
            .exec_shell(
                &verify_script(session.shell, &remote_path, expected_size),
                session.shell,
            )
            .await
            .map_err(|error| ClientError::Transport(error.to_string()))?;
        if result.exit_code != 0 {
            return Err(ClientError::Transport(
                "Attachment upload is incomplete or the file is no longer readable".into(),
            ));
        }
        Ok(())
    }

    pub async fn ssh_attachment_cancel(
        &self,
        session_id: String,
        remote_path: String,
    ) -> Result<(), ClientError> {
        let session = self.attachment_session(&session_id, Some(&remote_path))?;
        let result = session
            .client
            .exec_shell(&cancel_script(session.shell, &remote_path), session.shell)
            .await
            .map_err(|error| ClientError::Transport(error.to_string()))?;
        if result.exit_code != 0 {
            return Err(ClientError::Transport(
                "Could not remove the incomplete SSH attachment".into(),
            ));
        }
        self.ssh_attachments
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .remove(&(session_id, remote_path));
        Ok(())
    }
}
