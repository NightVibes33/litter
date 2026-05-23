use thiserror::Error;

#[derive(Debug, Error, uniffi::Error)]
pub enum ProotBootstrapError {
    #[error("Unsupported: {detail}")]
    Unsupported { detail: String },
    #[error("Missing artifact: {detail}")]
    MissingArtifact { detail: String },
    #[error("I/O error: {detail}")]
    Io { detail: String },
    #[error("Archive error: {detail}")]
    Archive { detail: String },
    #[error("Ptrace denied: {detail}")]
    PtraceDenied { detail: String },
    #[error("Already bootstrapped with a different configuration")]
    AlreadyBootstrapped,
}
