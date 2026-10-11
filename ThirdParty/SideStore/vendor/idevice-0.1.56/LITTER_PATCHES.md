Pinned source: jkcoxson/idevice commit a714d35d95dc16769f8a54a6168ccec6338b73c7, package idevice 0.1.56. Upstream declares MIT in Cargo.toml.

Remote pairing imports the existing rand_core 0.6 OsRng and Ed25519 signing trait directly, rather than through the optional RSA dependency. RustBridge selects its used services without enabling unused classic pair/certificate-generation code and vulnerable RustCrypto RSA. The existing UserDeniedPairing error is also enabled for remote_pairing, whose caller already uses it. RustBridge retains TSS image mounting and the TCP tunnel stack. No service API changes.

Optional classic-pairing certificate generation now uses OpenSSL RSA, preserving the SHA-256 signature, PKCS#8 private key, serial, validity, and root certificate extensions. Its internal ca module is private. RustBridge still does not enable classic pairing.
