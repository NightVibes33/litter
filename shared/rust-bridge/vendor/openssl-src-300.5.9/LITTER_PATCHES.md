# Bundled OpenSSL source update

Retains the openssl-src 300.5.5 build API and replaces its bundled OpenSSL
3.5.5 with the maintained LTS 3.5.9 release. Package version is 300.5.9+3.5.9.
The compressed, immutable upstream archive avoids introducing a million-line
expanded vendor tree. Cargo extracts it into generated OUT_DIR; builds perform
no network download. The build script verifies its SHA-256 before extraction.

Source: https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz

SHA-256: 603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a

The archive retains OpenSSL's LICENSE.txt and source provenance. The Rust
build wrapper retains its upstream MIT/Apache licenses. Source and build API
changes require review independently of registry advisory inventories.
