// Jackson Coxson; backend migration by Litter contributors.
// Preserve the pairing certificate format using maintained OpenSSL RSA.
use openssl::{
    asn1::Asn1Time,
    bn::BigNum,
    hash::MessageDigest,
    pkey::{PKey, Private, Public},
    rsa::Rsa,
    x509::{
        X509, X509NameBuilder,
        extension::{BasicConstraints, KeyUsage, SubjectKeyIdentifier},
    },
};

#[derive(Clone, Debug)]
pub struct CaReturn {
    pub host_cert: Vec<u8>,
    pub dev_cert: Vec<u8>,
    pub private_key: Vec<u8>,
}

fn make_cert(
    signing_key: &PKey<Private>,
    public_key: &PKey<Public>,
    common_name: Option<&str>,
) -> Result<X509, Box<dyn std::error::Error>> {
    let mut name = X509NameBuilder::new()?;
    if let Some(common_name) = common_name {
        name.append_entry_by_text("CN", common_name)?;
    }
    let name = name.build();
    let mut cert = X509::builder()?;
    cert.set_version(2)?;
    let serial = BigNum::from_u32(1)?.to_asn1_integer()?;
    cert.set_serial_number(&serial)?;
    cert.set_subject_name(&name)?;
    cert.set_issuer_name(&name)?;
    cert.set_pubkey(public_key)?;
    let not_before = Asn1Time::days_from_now(0)?;
    let not_after = Asn1Time::days_from_now(9 * 12 * 31)?;
    cert.set_not_before(&not_before)?;
    cert.set_not_after(&not_after)?;
    // Match the previous X509 Profile::Root extensions for both certificates.
    let subject_id = SubjectKeyIdentifier::new().build(&cert.x509v3_context(None, None))?;
    cert.append_extension(subject_id)?;
    cert.append_extension(BasicConstraints::new().critical().ca().build()?)?;
    cert.append_extension(
        KeyUsage::new()
            .critical()
            .key_cert_sign()
            .crl_sign()
            .build()?,
    )?;
    cert.sign(signing_key, MessageDigest::sha256())?;
    Ok(cert.build())
}

pub(crate) fn generate_certificates(
    device_public_key_pem: &[u8],
    private_key: Option<Rsa<Private>>,
) -> Result<CaReturn, Box<dyn std::error::Error>> {
    let device_public_key = PKey::from_rsa(Rsa::public_key_from_pem_pkcs1(device_public_key_pem)?)?;
    let host_key = PKey::from_rsa(match private_key {
        Some(key) => key,
        None => Rsa::generate(2048)?,
    })?;
    let host_public = PKey::public_key_from_der(&host_key.public_key_to_der()?)?;
    let host_cert = make_cert(&host_key, &host_public, None)?;
    let dev_cert = make_cert(&host_key, &device_public_key, Some("Device"))?;
    Ok(CaReturn {
        host_cert: host_cert.to_pem()?,
        dev_cert: dev_cert.to_pem()?,
        private_key: host_key.private_key_to_pem_pkcs8()?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn certificates_keep_pairing_keys_and_verify_with_host_key() {
        let device = Rsa::generate(2048).unwrap();
        let result =
            generate_certificates(&device.public_key_to_pem_pkcs1().unwrap(), None).unwrap();
        let host = PKey::private_key_from_pem(&result.private_key).unwrap();
        let host_cert = X509::from_pem(&result.host_cert).unwrap();
        let device_cert = X509::from_pem(&result.dev_cert).unwrap();
        assert!(host_cert.verify(&host).unwrap());
        assert!(device_cert.verify(&host).unwrap());
        assert!(host_cert.public_key().unwrap().public_eq(&host));
        let device_public = PKey::from_rsa(device).unwrap();
        assert!(device_cert.public_key().unwrap().public_eq(&device_public));
        assert_eq!(host.bits(), 2048);
        assert!(
            result
                .private_key
                .starts_with(b"-----BEGIN PRIVATE KEY-----")
        );
        assert!(generate_certificates(b"invalid device key", None).is_err());
    }
}
