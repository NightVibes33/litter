//! Provider device authorization shared by native mobile shells.
use super::ClientError;
use serde::Deserialize;
use std::{
    sync::Arc,
    time::{Duration, Instant},
};

const ISSUER: &str = "https://auth.openai.com";
const CLIENT_ID: &str = "app_EMoamEEZ73f0CkXaXp7hrann";

#[derive(uniffi::Record)]
pub struct DeviceLoginPrompt {
    pub verification_url: String,
    pub user_code: String,
    pub interval_seconds: u64,
}

#[derive(Deserialize, uniffi::Record)]
pub struct DeviceLoginAuthorization {
    pub authorization_code: String,
    pub code_verifier: String,
}

#[derive(Deserialize)]
struct CodeResponse {
    device_auth_id: String,
    #[serde(alias = "usercode")]
    user_code: String,
    #[serde(default)]
    interval: serde_json::Value,
}

#[derive(uniffi::Object)]
pub struct DeviceLogin {
    client: reqwest::Client,
    code: CodeResponse,
    started: Instant,
}

fn transport(_: impl std::fmt::Display) -> ClientError {
    // Authentication responses and authorization codes must never enter logs.
    ClientError::Transport(
        "Could not reach ChatGPT device authorization. Check your connection.".into(),
    )
}

fn interval(value: &serde_json::Value) -> u64 {
    value
        .as_u64()
        .or_else(|| value.as_str()?.parse().ok())
        .unwrap_or(5)
        .clamp(1, 60)
}

#[uniffi::export(async_runtime = "tokio")]
pub async fn start_device_login() -> Result<Arc<DeviceLogin>, ClientError> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(transport)?;
    let response = client
        .post(format!("{ISSUER}/api/accounts/deviceauth/usercode"))
        .json(&serde_json::json!({"client_id": CLIENT_ID}))
        .send()
        .await
        .map_err(transport)?;
    if !response.status().is_success() {
        return Err(ClientError::Rpc(format!("Device sign-in is unavailable (HTTP {}). Enable device code authorization in your ChatGPT security settings if required.", response.status().as_u16())));
    }
    let code: CodeResponse = response.json().await.map_err(transport)?;
    if code.device_auth_id.is_empty() || code.user_code.is_empty() {
        return Err(ClientError::Serialization(
            "Device sign-in returned an incomplete code.".into(),
        ));
    }
    Ok(Arc::new(DeviceLogin {
        client,
        code,
        started: Instant::now(),
    }))
}

#[uniffi::export(async_runtime = "tokio")]
impl DeviceLogin {
    pub fn prompt(&self) -> DeviceLoginPrompt {
        DeviceLoginPrompt {
            verification_url: format!("{ISSUER}/codex/device"),
            user_code: self.code.user_code.clone(),
            interval_seconds: interval(&self.code.interval),
        }
    }

    pub async fn poll(&self) -> Result<Option<DeviceLoginAuthorization>, ClientError> {
        self.poll_at(&format!("{ISSUER}/api/accounts/deviceauth/token"))
            .await
    }
}

impl DeviceLogin {
    async fn poll_at(&self, url: &str) -> Result<Option<DeviceLoginAuthorization>, ClientError> {
        if self.started.elapsed() >= Duration::from_secs(15 * 60) {
            return Err(ClientError::Rpc(
                "Sign-in code expired. Start again for a new code.".into(),
            ));
        }
        let response = self.client.post(url)
            .json(&serde_json::json!({"device_auth_id": self.code.device_auth_id, "user_code": self.code.user_code}))
            .send().await.map_err(transport)?;
        match response.status().as_u16() {
            403 | 404 => Ok(None),
            200..=299 => {
                let authorization: DeviceLoginAuthorization =
                    response.json().await.map_err(transport)?;
                if authorization.authorization_code.is_empty()
                    || authorization.code_verifier.is_empty()
                {
                    return Err(ClientError::Serialization(
                        "Device sign-in returned an incomplete authorization.".into(),
                    ));
                }
                Ok(Some(authorization))
            }
            status => Err(ClientError::Rpc(format!(
                "Device sign-in failed (HTTP {status}). Start again."
            ))),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn accepts_provider_interval_formats_and_bounds_polling() {
        assert_eq!(interval(&serde_json::json!("5")), 5);
        assert_eq!(interval(&serde_json::json!(10)), 10);
        assert_eq!(interval(&serde_json::Value::Null), 5);
        assert_eq!(interval(&serde_json::json!(0)), 1);
        assert_eq!(interval(&serde_json::json!(9999)), 60);
    }
    #[test]
    fn accepts_both_provider_code_spellings() {
        for key in ["user_code", "usercode"] {
            let code: CodeResponse =
                serde_json::from_value(serde_json::json!({"device_auth_id":"id", key:"ABCD"}))
                    .unwrap();
            assert_eq!(code.user_code, "ABCD");
        }
    }
    #[tokio::test]
    async fn polling_distinguishes_pending_approval_and_failure() {
        use std::io::{Read, Write};
        for (status, body, expected) in [
            (403, "{}", "pending"),
            (404, "{}", "pending"),
            (
                200,
                r#"{"authorization_code":"code","code_verifier":"verifier"}"#,
                "approved",
            ),
            (200, "{}", "error"),
            (429, "{}", "error"),
        ] {
            let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
            let url = format!("http://{}/", listener.local_addr().unwrap());
            let server = std::thread::spawn(move || {
                let (mut stream, _) = listener.accept().unwrap();
                let mut request = [0; 4096];
                let _ = stream.read(&mut request).unwrap();
                write!(stream, "HTTP/1.1 {status} Test\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).unwrap();
            });
            let login = DeviceLogin {
                client: reqwest::Client::builder().no_proxy().build().unwrap(),
                code: CodeResponse {
                    device_auth_id: "id".into(),
                    user_code: "user".into(),
                    interval: serde_json::Value::Null,
                },
                started: Instant::now(),
            };
            let result = login.poll_at(&url).await;
            match expected {
                "pending" => assert!(matches!(result, Ok(None))),
                "approved" => assert!(matches!(result, Ok(Some(_)))),
                _ => assert!(result.is_err()),
            }
            server.join().unwrap();
        }
    }

    #[tokio::test]
    async fn expired_code_never_contacts_provider() {
        let login = DeviceLogin {
            client: reqwest::Client::new(),
            code: CodeResponse {
                device_auth_id: "id".into(),
                user_code: "user".into(),
                interval: serde_json::Value::Null,
            },
            started: Instant::now() - Duration::from_secs(901),
        };
        assert!(matches!(
            login.poll_at("http://127.0.0.1:1").await,
            Err(ClientError::Rpc(_))
        ));
    }
}
