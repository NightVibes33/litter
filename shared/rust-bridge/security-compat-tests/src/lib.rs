#[cfg(test)]
mod tests {
    use std::hash::Hasher;

    #[test]
    fn terminal_styles_keep_legacy_names_and_escape_sequences() {
        let text: ansi_term::ANSIString = ansi_term::Colour::Red.bold().paint("warning");
        assert_eq!(text.to_string(), "\x1b[1;31mwarning\x1b[0m");
        let items = [
            ansi_term::Colour::Green.paint("ok"),
            ansi_term::Colour::Blue.paint("next"),
        ];
        let joined = ansi_term::ANSIStrings(&items).to_string();
        assert!(joined.contains("ok"));
        assert!(joined.contains("next"));
    }

    #[test]
    fn json_keeps_unicode_numbers_null_and_nested_arrays() {
        let text = r#"{"name":"雪🐈","items":[null,true,-42,1.25],"escaped":"line\nnext"}"#;
        let value = json::parse(text).unwrap();
        assert_eq!(value["name"].as_str(), Some("雪🐈"));
        assert!(value["items"][0].is_null());
        assert_eq!(value["items"][2].as_i32(), Some(-42));
        assert_eq!(json::parse(&value.dump()).unwrap(), value);
        assert!(json::parse("{} trailing").is_err());
        assert!(json::parse(r#"{"missing":}"#).is_err());
    }

    #[test]
    fn fx_hash_keeps_legacy_word_fingerprint() {
        let mut hash = fxhash::FxHasher64::default();
        hash.write_u64(0x0123456789abcdef);
        assert_eq!(hash.finish(), 6254456091980608027);
        let mut map = fxhash::FxHashMap::default();
        map.insert("key", 7);
        assert_eq!(map.get("key"), Some(&7));
    }

    paste::paste! { fn [<generated _ name>]() -> u8 { 19 } }

    #[test]
    fn maintained_pasting_macro_expands_legacy_invocations() {
        assert_eq!(generated_name(), 19);
    }

    #[test]
    fn portable_atomic_preserves_compare_exchange_semantics() {
        use atomic_polyfill::{AtomicUsize, Ordering};
        let counter = AtomicUsize::new(3);
        assert_eq!(
            counter.compare_exchange(3, 5, Ordering::SeqCst, Ordering::SeqCst),
            Ok(3)
        );
        assert_eq!(
            counter.compare_exchange(3, 7, Ordering::SeqCst, Ordering::SeqCst),
            Err(5)
        );
        assert_eq!(counter.load(Ordering::Acquire), 5);
    }
}

#[cfg(test)]
mod rsa_tests {
    use signature::{Signer, Verifier};
    use ssh_key::{HashAlg, PrivateKey};

    fn fixture() -> PrivateKey {
        PrivateKey::from_openssh(include_str!(
            "../../vendor/ssh-key-0.7.0-rc.11/tests/examples/id_rsa_3072"
        ))
        .unwrap()
    }

    #[test]
    fn rsa_sha2_signatures_verify_and_reject_changed_messages() {
        let key = fixture();
        let pair = key.key_data().rsa().unwrap();
        for hash in [HashAlg::Sha256, HashAlg::Sha512] {
            let signature = (pair, Some(hash))
                .try_sign(b"backend migration fixture")
                .unwrap();
            pair.public()
                .verify(b"backend migration fixture", &signature)
                .unwrap();
            assert!(pair
                .public()
                .verify(b"altered message", &signature)
                .is_err());
        }
        assert!((pair, None)
            .try_sign(b"legacy SHA1 authentication")
            .is_err());
    }

    #[test]
    fn rsa_pkcs8_and_openssh_round_trips_keep_public_identity() {
        let original = fixture();
        let der = russh::keys::pkcs8::encode_pkcs8(&original).unwrap();
        use ssh_key::LineEnding;
        let pem = original.to_openssh(LineEnding::LF).unwrap();
        let restored = PrivateKey::from_openssh(pem.as_str()).unwrap();
        assert_eq!(original.public_key(), restored.public_key());
        use base64::Engine;
        let pkcs8 = format!(
            "-----BEGIN PRIVATE KEY-----\n{}\n-----END PRIVATE KEY-----\n",
            base64::engine::general_purpose::STANDARD.encode(&der)
        );
        let restored_pkcs8 = russh::keys::decode_secret_key(&pkcs8, None).unwrap();
        // PKCS#8 has no OpenSSH comment field; compare the cryptographic identity.
        assert_eq!(
            original.public_key().key_data(),
            restored_pkcs8.public_key().key_data()
        );
        let pair = restored_pkcs8.key_data().rsa().unwrap();
        let signature = (pair, Some(HashAlg::Sha256))
            .try_sign(b"restored private key")
            .unwrap();
        original
            .key_data()
            .rsa()
            .unwrap()
            .public()
            .verify(b"restored private key", &signature)
            .unwrap();
        assert!(ssh_key::private::RsaKeypair::from_pkcs1_der(b"invalid key").is_err());
    }
}

#[cfg(test)]
mod openssh_fixture_tests {
    #[test]
    fn rsa_verifies_independent_openssh_signature_fixture() {
        let public: ssh_key::PublicKey =
            include_str!("../../vendor/ssh-key-0.7.0-rc.11/tests/examples/id_rsa_3072.pub")
                .parse()
                .unwrap();
        let signature: ssh_key::SshSig =
            include_str!("../../vendor/ssh-key-0.7.0-rc.11/tests/examples/sshsig_rsa_3072")
                .parse()
                .unwrap();
        public.verify("example", b"testing", &signature).unwrap();
        assert!(public
            .verify("example", b"different message", &signature)
            .is_err());
        assert!(public
            .verify("different namespace", b"testing", &signature)
            .is_err());
    }
}

#[cfg(test)]
mod rsa_generation_tests {
    use signature::{Signer, Verifier};
    #[test]
    fn generated_rsa_key_signs_and_verifies_through_system_backend() {
        let key = ssh_key::PrivateKey::random(
            &mut russh::keys::key::safe_rng(),
            ssh_key::Algorithm::Rsa {
                hash: Some(ssh_key::HashAlg::Sha256),
            },
        )
        .unwrap();
        let pair = key.key_data().rsa().unwrap();
        assert!(pair.key_size() >= 2048);
        let signature = pair.try_sign(b"generated key fixture").unwrap();
        pair.public()
            .verify(b"generated key fixture", &signature)
            .unwrap();
    }
}
