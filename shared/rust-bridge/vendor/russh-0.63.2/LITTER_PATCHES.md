# Maintained RSA backend migration

Pinned crates.io source: russh-0.63.2. Original upstream licenses and test fixtures are retained; fixture private keys are public upstream test data.

RSA import/export and SHA-256/SHA-512 signing and verification use AWS-LC instead of the affected RustCrypto rsa implementation. OpenSSH components retain their encoding and fingerprint. Missing OpenSSH CRT exponents are derived through crypto-bigint's constant-time remainder operation with zeroized temporary storage; AWS-LC validates the resulting key. Key generation uses AWS-LC's system CSPRNG. SHA-1 signature verification remains available for legacy host keys, while SHA-1 private-key authentication signing is rejected. AWS-LC requires RSA private keys of at least 2048 bits; this rejects weak legacy private keys.

This is a root-owned backend patch, not an upstream fixed release. Validate key import/export, signatures, negative cases, and both platform builds before merge.
