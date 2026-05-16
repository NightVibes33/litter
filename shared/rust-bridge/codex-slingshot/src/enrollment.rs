use std::path::{Path, PathBuf};

use async_trait::async_trait;
use serde::{Deserialize, Serialize};

use crate::device_key::DeviceKeyEnrollment;
use crate::types::ClientEnrollmentTokenResponse;

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct SlingshotControllerSession {
    pub client_id: String,
    pub account_user_id: String,
    pub remote_control_token: String,
    pub expires_at: String,
    pub scopes: Vec<String>,
    pub device_key: DeviceKeyEnrollment,
}

impl SlingshotControllerSession {
    pub fn from_finish(
        device_key: DeviceKeyEnrollment,
        finish: ClientEnrollmentTokenResponse,
    ) -> Self {
        Self {
            client_id: finish.client_id,
            account_user_id: finish.account_user_id,
            remote_control_token: finish.remote_control_token,
            expires_at: finish.expires_at,
            scopes: finish.scopes,
            device_key,
        }
    }
}

#[async_trait]
pub trait EnrollmentStore: Send + Sync {
    async fn load(&self) -> Result<Option<String>, std::io::Error>;
    async fn save(&self, client_id: &str) -> Result<(), std::io::Error>;
    async fn clear(&self) -> Result<(), std::io::Error>;
}

#[derive(Default)]
pub struct MemoryEnrollmentStore {
    client_id: std::sync::Mutex<Option<String>>,
}

impl MemoryEnrollmentStore {
    pub fn new(client_id: Option<String>) -> Self {
        Self {
            client_id: std::sync::Mutex::new(client_id),
        }
    }
}

#[async_trait]
impl EnrollmentStore for MemoryEnrollmentStore {
    async fn load(&self) -> Result<Option<String>, std::io::Error> {
        Ok(match self.client_id.lock() {
            Ok(guard) => guard.clone(),
            Err(error) => error.into_inner().clone(),
        })
    }

    async fn save(&self, client_id: &str) -> Result<(), std::io::Error> {
        match self.client_id.lock() {
            Ok(mut guard) => *guard = Some(client_id.to_string()),
            Err(error) => *error.into_inner() = Some(client_id.to_string()),
        }
        Ok(())
    }

    async fn clear(&self) -> Result<(), std::io::Error> {
        match self.client_id.lock() {
            Ok(mut guard) => *guard = None,
            Err(error) => *error.into_inner() = None,
        }
        Ok(())
    }
}

pub struct FileEnrollmentStore {
    path: PathBuf,
}

impl FileEnrollmentStore {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self { path: path.into() }
    }

    pub fn for_account(root: impl AsRef<Path>, account_id: &str) -> Self {
        let filename = format!("slingshot-{}.json", sanitize_account_id(account_id));
        Self::new(root.as_ref().join(filename))
    }
}

#[derive(serde::Serialize, serde::Deserialize)]
struct EnrollmentFile {
    client_id: String,
}

#[async_trait]
impl EnrollmentStore for FileEnrollmentStore {
    async fn load(&self) -> Result<Option<String>, std::io::Error> {
        match std::fs::read(&self.path) {
            Ok(bytes) => {
                let decoded = serde_json::from_slice::<EnrollmentFile>(&bytes)
                    .map_err(std::io::Error::other)?;
                Ok(Some(decoded.client_id))
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(error),
        }
    }

    async fn save(&self, client_id: &str) -> Result<(), std::io::Error> {
        if let Some(parent) = self.path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let bytes = serde_json::to_vec(&EnrollmentFile {
            client_id: client_id.to_string(),
        })
        .map_err(std::io::Error::other)?;
        std::fs::write(&self.path, bytes)
    }

    async fn clear(&self) -> Result<(), std::io::Error> {
        match std::fs::remove_file(&self.path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
    }
}

fn sanitize_account_id(value: &str) -> String {
    let mut out = value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                ch
            } else {
                '_'
            }
        })
        .collect::<String>();
    if out.is_empty() {
        out = "default".to_string();
    }
    out
}
