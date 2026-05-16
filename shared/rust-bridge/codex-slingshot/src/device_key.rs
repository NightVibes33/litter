use base64::Engine as _;
use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use p256::ecdsa::signature::Signer;
use p256::ecdsa::{Signature, SigningKey};
use p256::pkcs8::{DecodePrivateKey, EncodePrivateKey, EncodePublicKey};
use rand_core::OsRng;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tracing::warn;

use crate::errors::SlingshotApiError;
use crate::types::{
    DeviceIdentity, DeviceKeyChallenge, DeviceKeyConnectionChallenge, DeviceKeyConnectionProof,
    DeviceKeyProof,
};

const DEVICE_KEY_SIGNING_DOMAIN: &str = "codex-device-key-sign-payload/v1";
const DEVICE_KEY_ALGORITHM: &str = "ecdsa_p256_sha256";
const DEVICE_KEY_PROTECTION_CLASS: &str = "os_protected_nonextractable";

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct DeviceKeyEnrollment {
    pub account_user_id: String,
    pub client_id: String,
    pub key_id: String,
    pub public_key_spki_der_base64: String,
    pub algorithm: String,
    pub protection_class: String,
    private_key_pkcs8_der_base64: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DeviceIdentityHashPayload<'a> {
    algorithm: &'a str,
    key_id: &'a str,
    protection_class: &'a str,
    public_key_spki_der_base64: &'a str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct EnrollmentSignPayload<'a> {
    account_user_id: &'a str,
    audience: &'a str,
    challenge_expires_at: i64,
    challenge_id: &'a str,
    client_id: &'a str,
    device_identity_sha256_base64url: &'a str,
    nonce: &'a str,
    target_origin: &'a str,
    target_path: &'a str,
    #[serde(rename = "type")]
    kind: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ConnectionSignPayload<'a> {
    account_user_id: &'a str,
    audience: &'a str,
    client_id: &'a str,
    nonce: &'a str,
    scopes: &'a [String],
    session_id: &'a str,
    target_origin: &'a str,
    target_path: &'a str,
    token_expires_at: i64,
    token_sha256_base64url: &'a str,
    #[serde(rename = "type")]
    kind: &'static str,
}

#[derive(Serialize)]
struct SignedPayloadEnvelope<'a, T: Serialize> {
    domain: &'static str,
    payload: &'a T,
}

impl DeviceKeyEnrollment {
    pub fn generate(account_user_id: String, client_id: String) -> Result<Self, SlingshotApiError> {
        let signing_key = SigningKey::random(&mut OsRng);
        let private_key_pkcs8_der_base64 = STANDARD.encode(
            signing_key
                .to_pkcs8_der()
                .map_err(|error| SlingshotApiError::Crypto(error.to_string()))?
                .as_bytes(),
        );
        let public_key_spki_der_base64 = STANDARD.encode(
            signing_key
                .verifying_key()
                .to_public_key_der()
                .map_err(|error| SlingshotApiError::Crypto(error.to_string()))?
                .as_bytes(),
        );
        Ok(Self {
            account_user_id,
            client_id,
            key_id: format!("dk_{}", uuid::Uuid::new_v4().simple()),
            public_key_spki_der_base64,
            algorithm: DEVICE_KEY_ALGORITHM.to_string(),
            protection_class: DEVICE_KEY_PROTECTION_CLASS.to_string(),
            private_key_pkcs8_der_base64,
        })
    }

    pub fn device_identity(&self) -> DeviceIdentity {
        DeviceIdentity {
            key_id: self.key_id.clone(),
            public_key_spki_der_base64: self.public_key_spki_der_base64.clone(),
            algorithm: self.algorithm.clone(),
            protection_class: self.protection_class.clone(),
        }
    }

    pub fn sign_enrollment_challenge(
        &self,
        challenge: &DeviceKeyChallenge,
        expected_target_origin: &str,
        expected_target_path: &str,
        require_device_identity_hash: bool,
    ) -> Result<DeviceKeyProof, SlingshotApiError> {
        self.validate_enrollment_challenge(
            challenge,
            expected_target_origin,
            expected_target_path,
            require_device_identity_hash,
        )?;
        let device_identity_hash = self.device_identity_hash()?;
        let payload = EnrollmentSignPayload {
            account_user_id: &challenge.account_user_id,
            audience: &challenge.audience,
            challenge_expires_at: challenge.challenge_expires_at,
            challenge_id: &challenge.challenge_id,
            client_id: &challenge.client_id,
            device_identity_sha256_base64url: &device_identity_hash,
            nonce: &challenge.nonce,
            target_origin: &challenge.target_origin,
            target_path: &challenge.target_path,
            kind: "remoteControlClientEnrollment",
        };
        let signature = self.sign_payload(&payload)?;
        Ok(DeviceKeyProof {
            challenge_token: challenge.challenge_token.clone(),
            key_id: self.key_id.clone(),
            signature_der_base64: signature.signature_der_base64,
            signed_payload_base64: signature.signed_payload_base64,
            algorithm: signature.algorithm,
        })
    }

    pub fn sign_connection_challenge(
        &self,
        challenge: &DeviceKeyConnectionChallenge,
    ) -> Result<DeviceKeyConnectionProof, SlingshotApiError> {
        if challenge.account_user_id != self.account_user_id
            || challenge.client_id != self.client_id
        {
            return Err(SlingshotApiError::DeviceKeyChallengeMismatch(
                "connection challenge does not match local enrollment".to_string(),
            ));
        }
        let payload = ConnectionSignPayload {
            account_user_id: &challenge.account_user_id,
            audience: &challenge.audience,
            client_id: &challenge.client_id,
            nonce: &challenge.nonce,
            scopes: &challenge.scopes,
            session_id: &challenge.session_id,
            target_origin: &challenge.target_origin,
            target_path: &challenge.target_path,
            token_expires_at: challenge.token_expires_at,
            token_sha256_base64url: &challenge.token_sha256_base64url,
            kind: "remoteControlClientConnection",
        };
        let signature = self.sign_payload(&payload)?;
        Ok(DeviceKeyConnectionProof {
            kind: "device_key_proof".to_string(),
            key_id: self.key_id.clone(),
            signature_der_base64: signature.signature_der_base64,
            signed_payload_base64: signature.signed_payload_base64,
            algorithm: signature.algorithm,
        })
    }

    fn validate_enrollment_challenge(
        &self,
        challenge: &DeviceKeyChallenge,
        expected_target_origin: &str,
        expected_target_path: &str,
        require_device_identity_hash: bool,
    ) -> Result<(), SlingshotApiError> {
        let local_hash = self.device_identity_hash()?;
        if challenge.account_user_id != self.account_user_id
            || challenge.client_id != self.client_id
            || challenge.target_origin != expected_target_origin
            || challenge.target_path != expected_target_path
        {
            warn!(
                target: "codex_slingshot",
                local_account_user_id = %self.account_user_id,
                challenge_account_user_id = %challenge.account_user_id,
                local_client_id = %self.client_id,
                challenge_client_id = %challenge.client_id,
                expected_target_origin = %expected_target_origin,
                challenge_target_origin = %challenge.target_origin,
                expected_target_path = %expected_target_path,
                challenge_target_path = %challenge.target_path,
                local_device_identity_hash = %local_hash,
                challenge_device_identity_hash = ?challenge.device_identity_hash,
                "slingshot enrollment challenge mismatch"
            );
            return Err(SlingshotApiError::DeviceKeyChallengeMismatch(
                "enrollment challenge does not match local enrollment".to_string(),
            ));
        }
        match challenge.device_identity_hash.as_deref() {
            Some(remote_hash) if remote_hash == local_hash => Ok(()),
            Some(remote_hash) => {
                warn!(
                    target: "codex_slingshot",
                    local_device_identity_hash = %local_hash,
                    challenge_device_identity_hash = %remote_hash,
                    "slingshot enrollment challenge device identity hash mismatch"
                );
                Err(SlingshotApiError::DeviceKeyChallengeMismatch(
                    "enrollment challenge does not match local device identity".to_string(),
                ))
            }
            None if require_device_identity_hash => {
                warn!(
                    target: "codex_slingshot",
                    local_device_identity_hash = %local_hash,
                    "slingshot enrollment challenge missing required device identity hash"
                );
                Err(SlingshotApiError::DeviceKeyChallengeMismatch(
                    "enrollment challenge is missing device identity hash".to_string(),
                ))
            }
            None => Ok(()),
        }
    }

    pub(crate) fn device_identity_hash(&self) -> Result<String, SlingshotApiError> {
        let payload = DeviceIdentityHashPayload {
            algorithm: &self.algorithm,
            key_id: &self.key_id,
            protection_class: &self.protection_class,
            public_key_spki_der_base64: &self.public_key_spki_der_base64,
        };
        let json = serde_json::to_string(&payload)?;
        Ok(URL_SAFE_NO_PAD.encode(Sha256::digest(json.as_bytes())))
    }

    fn sign_payload<T: Serialize>(
        &self,
        payload: &T,
    ) -> Result<SignedDevicePayload, SlingshotApiError> {
        let envelope = SignedPayloadEnvelope {
            domain: DEVICE_KEY_SIGNING_DOMAIN,
            payload,
        };
        let signed_payload = serde_json::to_vec(&envelope)?;
        let key_der = STANDARD
            .decode(&self.private_key_pkcs8_der_base64)
            .map_err(|error| SlingshotApiError::Crypto(error.to_string()))?;
        let signing_key = SigningKey::from_pkcs8_der(&key_der)
            .map_err(|error| SlingshotApiError::Crypto(error.to_string()))?;
        let signature: Signature = signing_key.sign(&signed_payload);
        Ok(SignedDevicePayload {
            signature_der_base64: STANDARD.encode(signature.to_der().as_bytes()),
            signed_payload_base64: STANDARD.encode(signed_payload),
            algorithm: self.algorithm.clone(),
        })
    }
}

struct SignedDevicePayload {
    signature_der_base64: String,
    signed_payload_base64: String,
    algorithm: String,
}
