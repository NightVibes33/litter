//! SSH session bring-up and teardown: TCP dial → russh handshake →
//! host-key verification (via the user's `host_key_callback`) →
//! authenticate → ready-to-use [`SshClient`].

use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use futures::future::BoxFuture;
use russh::client::{self, Handle};
use russh::keys::PublicKeyOrCertificate;
use russh::keys::{decode_secret_key, HashAlg, PrivateKeyWithHashAlg};
use tokio::sync::Mutex;
use tracing::{error, info, warn};

use super::{
    append_bridge_info_log, normalize_host, SshAuth, SshClient, SshCredentials, SshDetection,
    SshError, CONNECT_TIMEOUT, KEEPALIVE_INTERVAL, SSH_CHANNEL_BUFFER_SIZE,
    SSH_CHANNEL_WINDOW_SIZE, SSH_MAX_PACKET_SIZE,
};

pub(super) type HostKeyCallback = Arc<dyn Fn(&str) -> BoxFuture<'static, bool> + Send + Sync>;

pub(super) struct ClientHandler {
    pub(super) host_key_cb: HostKeyCallback,
    /// If the callback rejects the key we store the fingerprint so we can
    /// surface it in [`SshError::HostKeyVerification`].
    pub(super) rejected_fingerprint: Arc<Mutex<Option<String>>>,
}

#[async_trait]
impl client::Handler for ClientHandler {
    type Error = russh::Error;

    fn check_server_key(
        &mut self,
        server_public_key: &PublicKeyOrCertificate,
    ) -> impl std::future::Future<Output = Result<bool, Self::Error>> + Send {
        let fp = format!(
            "{}",
            server_public_key.public_key().fingerprint(HashAlg::Sha256)
        );
        // Certificate authority/principal trust is not represented by the
        // fingerprint callback. Keep accepting only explicitly approved raw keys.
        let is_certificate = server_public_key.certificate().is_some();
        let rejected_fingerprint = Arc::clone(&self.rejected_fingerprint);
        let callback = Arc::clone(&self.host_key_cb);
        async move {
            let accepted = !is_certificate && callback(&fp).await;
            if !accepted {
                *rejected_fingerprint.lock().await = Some(fp);
            }
            Ok(accepted)
        }
    }
}

impl SshClient {
    /// Open an SSH connection to `credentials.host:credentials.port`.
    ///
    /// `host_key_callback` is invoked with the SHA-256 fingerprint of the
    /// server's public key. Return `true` to accept, `false` to reject.
    pub async fn connect(
        credentials: SshCredentials,
        host_key_callback: Box<dyn Fn(&str) -> BoxFuture<'static, bool> + Send + Sync>,
    ) -> Result<Self, SshError> {
        let macos_keychain_password = if credentials.unlock_macos_keychain {
            match &credentials.auth {
                SshAuth::Password(password) => Some(password.clone()),
                SshAuth::PrivateKey { .. } => None,
            }
        } else {
            None
        };
        let auth_kind = match &credentials.auth {
            SshAuth::Password(_) => "password",
            SshAuth::PrivateKey { .. } => "key",
        };
        let rejected_fp = Arc::new(Mutex::new(None));

        let handler = ClientHandler {
            host_key_cb: Arc::from(host_key_callback),
            rejected_fingerprint: Arc::clone(&rejected_fp),
        };

        let config = client::Config {
            keepalive_interval: Some(KEEPALIVE_INTERVAL),
            keepalive_max: 3,
            inactivity_timeout: None,
            window_size: SSH_CHANNEL_WINDOW_SIZE,
            maximum_packet_size: SSH_MAX_PACKET_SIZE,
            channel_buffer_size: SSH_CHANNEL_BUFFER_SIZE,
            nodelay: true,
            ..Default::default()
        };

        let addr = format!("{}:{}", normalize_host(&credentials.host), credentials.port);
        info!(
            "SSH connect start addr={} username={} auth={} nodelay={} window_size={} maximum_packet_size={} channel_buffer_size={}",
            addr,
            credentials.username,
            auth_kind,
            config.nodelay,
            config.window_size,
            config.maximum_packet_size,
            config.channel_buffer_size
        );
        append_bridge_info_log(&format!(
            "ssh_connect_start addr={} username={} auth={} nodelay={} window_size={} maximum_packet_size={} channel_buffer_size={}",
            addr,
            credentials.username,
            auth_kind,
            config.nodelay,
            config.window_size,
            config.maximum_packet_size,
            config.channel_buffer_size
        ));

        let connect_result = tokio::time::timeout(
            CONNECT_TIMEOUT,
            client::connect(Arc::new(config), &*addr, handler),
        )
        .await;
        let mut handle = match connect_result {
            Ok(Ok(handle)) => handle,
            Ok(Err(error)) => {
                // russh surfaces a rejected host key as `UnknownKey` from
                // `client::connect`; check the rejected-fingerprint flag
                // before falling back to a generic connect error so callers
                // can distinguish a changed host key from an unknown one.
                if let Some(fp) = rejected_fp.lock().await.take() {
                    warn!("SSH host key rejected addr={} fingerprint={}", addr, fp);
                    append_bridge_info_log(&format!(
                        "ssh_host_key_rejected addr={} fingerprint={}",
                        addr, fp
                    ));
                    return Err(SshError::HostKeyVerification { fingerprint: fp });
                }
                error!("SSH connect failed addr={} error={:?}", addr, error);
                append_bridge_info_log(&format!(
                    "ssh_connect_failed addr={} error_display={} error_debug={:?}",
                    addr, error, error
                ));
                return Err(SshError::ConnectionFailed(format!("{error}")));
            }
            Err(_) => {
                warn!("SSH connect timed out addr={}", addr);
                append_bridge_info_log(&format!("ssh_connect_timeout addr={}", addr));
                return Err(SshError::Timeout);
            }
        };

        // If the handler rejected the key, surface a specific error.
        if let Some(fp) = rejected_fp.lock().await.take() {
            warn!("SSH host key rejected addr={} fingerprint={}", addr, fp);
            append_bridge_info_log(&format!(
                "ssh_host_key_rejected addr={} fingerprint={}",
                addr, fp
            ));
            return Err(SshError::HostKeyVerification { fingerprint: fp });
        }

        let auth_result = match &credentials.auth {
            SshAuth::Password(pw) => handle
                .authenticate_password(&credentials.username, pw)
                .await
                .map_err(|e| {
                    warn!("SSH password auth failed addr={} error={:?}", addr, e);
                    append_bridge_info_log(&format!(
                        "ssh_auth_failed addr={} method=password error_display={} error_debug={:?}",
                        addr, e, e
                    ));
                    SshError::AuthFailed(format!("{e}"))
                })?,
            SshAuth::PrivateKey {
                key_pem,
                passphrase,
            } => {
                let key = decode_secret_key(key_pem, passphrase.as_deref())
                    .map_err(|e| SshError::AuthFailed(format!("bad private key: {e}")))?;
                let key = PrivateKeyWithHashAlg::new(
                    Arc::new(key),
                    handle.best_supported_rsa_hash().await.map_err(|e| {
                        warn!("SSH RSA hash negotiation failed addr={} error={:?}", addr, e);
                        append_bridge_info_log(&format!(
                            "ssh_auth_failed addr={} method=key_hash error_display={} error_debug={:?}",
                            addr, e, e
                        ));
                        SshError::AuthFailed(format!("{e}"))
                    })?
                    .flatten(),
                );
                handle
                    .authenticate_publickey(&credentials.username, key)
                    .await
                    .map_err(|e| {
                        warn!("SSH key auth failed addr={} error={:?}", addr, e);
                        append_bridge_info_log(&format!(
                            "ssh_auth_failed addr={} method=key error_display={} error_debug={:?}",
                            addr, e, e
                        ));
                        SshError::AuthFailed(format!("{e}"))
                    })?
            }
        };

        if !auth_result.success() {
            warn!(
                "SSH auth rejected by server addr={} username={}",
                addr, credentials.username
            );
            append_bridge_info_log(&format!(
                "ssh_auth_rejected addr={} username={}",
                addr, credentials.username
            ));
            return Err(SshError::AuthFailed("server rejected credentials".into()));
        }

        info!("SSH connected and authenticated to {addr}");
        append_bridge_info_log(&format!(
            "ssh_connect_success addr={} username={}",
            addr, credentials.username
        ));

        Ok(Self::new_connected(handle, macos_keychain_password))
    }

    /// Internal constructor used after a successful handshake.
    pub(super) fn new_connected(
        handle: Handle<ClientHandler>,
        macos_keychain_password: Option<String>,
    ) -> Self {
        Self {
            handle: Arc::new(Mutex::new(handle)),
            forward_tasks: Mutex::new(HashMap::new()),
            macos_keychain_password,
            detection: std::sync::Mutex::new(SshDetection::default()),
            shell_probe: Mutex::new(()),
        }
    }

    /// Whether the SSH session appears to still be connected.
    pub fn is_connected(&self) -> bool {
        match self.handle.try_lock() {
            Ok(h) => !h.is_closed(),
            Err(_) => true, // locked = in use = presumably connected
        }
    }

    /// Disconnect the SSH session, aborting any port forwards.
    pub async fn disconnect(&self) {
        // Abort all forwarding tasks.
        let mut tasks = self.forward_tasks.lock().await;
        for (_, task) in tasks.drain() {
            task.task.abort();
        }
        drop(tasks);

        let handle = self.handle.lock().await;
        let _ = handle
            .disconnect(russh::Disconnect::ByApplication, "bye", "en")
            .await;
    }
}

#[cfg(test)]
mod host_key_tests {
    use super::*;
    use russh::client::Handler as _;
    use russh::keys::{Algorithm, PrivateKey};

    fn test_key() -> PrivateKey {
        PrivateKey::random(&mut russh::keys::key::safe_rng(), Algorithm::Ed25519).unwrap()
    }

    fn handler(accept: bool) -> ClientHandler {
        ClientHandler {
            host_key_cb: Arc::new(move |_| Box::pin(async move { accept })),
            rejected_fingerprint: Arc::new(Mutex::new(None)),
        }
    }

    #[tokio::test]
    async fn approved_raw_host_key_is_accepted() {
        let key = test_key().public_key().clone().into();
        let mut client = handler(true);
        assert!(client.check_server_key(&key).await.unwrap());
        assert!(client.rejected_fingerprint.lock().await.is_none());
    }

    #[tokio::test]
    async fn rejected_raw_host_key_records_its_fingerprint() {
        let public_key = test_key().public_key().clone();
        let fingerprint = public_key.fingerprint(HashAlg::Sha256).to_string();
        let mut client = handler(false);
        assert!(!client.check_server_key(&public_key.into()).await.unwrap());
        assert_eq!(
            client.rejected_fingerprint.lock().await.as_deref(),
            Some(fingerprint.as_str())
        );
    }

    #[tokio::test]
    async fn certificate_cannot_bypass_raw_key_approval_policy() {
        use russh::keys::ssh_key::certificate::{Builder, CertType};
        let key = test_key();
        let mut builder = Builder::new(
            vec![1; 32],
            key.public_key().key_data().clone(),
            0,
            u64::MAX,
        )
        .unwrap();
        builder.cert_type(CertType::Host).unwrap();
        builder.key_id("host-key-policy-test").unwrap();
        builder.valid_principal("localhost").unwrap();
        let certificate = builder.sign(&key).unwrap();
        let mut client = handler(true);
        assert!(!client.check_server_key(&certificate.into()).await.unwrap());
        assert!(client.rejected_fingerprint.lock().await.is_some());
    }
}
