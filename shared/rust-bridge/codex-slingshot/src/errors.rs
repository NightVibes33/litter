use thiserror::Error;

#[derive(Error, Debug, Clone, PartialEq)]
pub enum SlingshotTransportError {
    #[error("invalid server payload: {0}")]
    InvalidServerPayload(serde_json::Value),
    #[error("server error: {0}")]
    ServerError(String),
    #[error("invalid client payload")]
    InvalidClientPayload,
    #[error("invalid pong status")]
    InvalidPongStatus,
    #[error("invalid skip_history")]
    InvalidSkipHistory,
    #[error("missing environment id")]
    MissingEnvironmentId,
    #[error("missing message")]
    MissingMessage,
    #[error("missing sequence id")]
    MissingSequenceId,
    #[error("missing stream id")]
    MissingStreamId,
}

#[derive(Error, Debug)]
pub enum SlingshotApiError {
    #[error("HTTP request failed: {0}")]
    Http(#[from] reqwest::Error),
    #[error("websocket request failed: {0}")]
    WebSocket(String),
    #[error("HTTP request failed for {context}: HTTP status {status}; body: {body}")]
    Status {
        context: &'static str,
        status: reqwest::StatusCode,
        body: String,
    },
    #[error(
        "failed to decode {context} response ({status}, content-type {content_type}): {source}; body: {body}"
    )]
    Decode {
        context: &'static str,
        status: reqwest::StatusCode,
        content_type: String,
        body: String,
        #[source]
        source: serde_json::Error,
    },
    #[error("invalid header value: {0}")]
    Header(#[from] reqwest::header::InvalidHeaderValue),
    #[error("invalid base URL: {0}")]
    Url(String),
    #[error("client is not enrolled")]
    MissingClientId,
    #[error("client session token is not available")]
    MissingClientSessionToken,
    #[error("device key is not available")]
    MissingDeviceKey,
    #[error("device-key challenge mismatch: {0}")]
    DeviceKeyChallengeMismatch(String),
    #[error("crypto error: {0}")]
    Crypto(String),
    #[error(
        "Slingshot client enrollment now requires /client/enroll/start followed by /client/enroll/finish with a device-key proof and fresh remote-control authorization"
    )]
    ClientEnrollmentRequiresFinish,
    #[error("transport error: {0}")]
    Transport(#[from] SlingshotTransportError),
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}
