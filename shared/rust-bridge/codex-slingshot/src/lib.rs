//! OpenAI Slingshot relay transport for Codex app-server.
//!
//! The relay wraps app-server JSON-RPC frames in `RemoteControlEnvelope`
//! records. This crate exposes the typed REST surface plus an `AsyncRead` /
//! `AsyncWrite` adapter that lets the existing upstream
//! `RemoteAppServerClient::connect_json_line_stream` run over Slingshot.

pub mod api;
pub mod device_key;
pub mod enrollment;
pub mod envelope;
pub mod errors;
pub mod stream;
pub mod types;

pub use api::{SlingshotApi, SlingshotConfig};
pub use device_key::DeviceKeyEnrollment;
pub use enrollment::{
    EnrollmentStore, FileEnrollmentStore, MemoryEnrollmentStore, SlingshotControllerSession,
};
pub use envelope::{EnvelopeType, KnownPongStatus, RemoteControlEnvelope};
pub use errors::{SlingshotApiError, SlingshotTransportError};
pub use stream::{SlingshotFraming, SlingshotJsonLineStream};
pub use types::{
    ClientEnrollmentFinishRequest, ClientEnrollmentResponse, ClientEnrollmentStartResponse,
    ClientEnrollmentTokenResponse, ClientRefreshFinishRequest, ClientRefreshStartRequest,
    DeviceIdentity, DeviceKeyChallenge, DeviceKeyConnectionChallenge, DeviceKeyConnectionProof,
    DeviceKeyProof, EnvironmentKind, EnvironmentUpdateRequest, KnownOperatingSystem,
    OperatingSystem, SlingshotEnvironment, SlingshotThreadStatus, SlingshotThreadSummary,
    ThreadsPage,
};

use std::io::Error as IoError;
use std::io::ErrorKind;

use codex_app_server_client::{AppServerClient, RemoteAppServerClient, RemoteAppServerConnectArgs};

/// Connect an upstream app-server client through one Slingshot environment.
pub async fn connect_app_server_client(
    api: SlingshotApi,
    environment_id: String,
    args: RemoteAppServerConnectArgs,
) -> std::io::Result<AppServerClient> {
    let stream_id = uuid::Uuid::new_v4().to_string();
    let stream = SlingshotJsonLineStream::connect(api, environment_id.clone(), stream_id).await?;
    let label = format!("slingshot://{environment_id}");
    let remote = RemoteAppServerClient::connect_json_line_stream(stream, args, label)
        .await
        .map_err(|error| {
            IoError::new(
                ErrorKind::ConnectionAborted,
                format!("slingshot app-server handshake failed: {error}"),
            )
        })?;
    Ok(AppServerClient::Remote(remote))
}
