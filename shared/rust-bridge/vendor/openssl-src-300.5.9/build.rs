use sha2::{Digest, Sha256};
use std::{env, path::PathBuf};

fn main() {
    println!("cargo:rerun-if-changed=openssl-3.5.9.tar.gz");
    let source = include_bytes!("openssl-3.5.9.tar.gz");
    let digest = format!("{:x}", Sha256::digest(source));
    assert_eq!(digest, "603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a",
               "OpenSSL source archive checksum mismatch");
    let destination = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo OUT_DIR"));
    let source_dir = destination.join("openssl-3.5.9");
    if source_dir.exists() {
        std::fs::remove_dir_all(&source_dir).expect("remove previous generated OpenSSL source");
    }
    let decoder = flate2::read::GzDecoder::new(&source[..]);
    tar::Archive::new(decoder).unpack(&destination).expect("unpack pinned OpenSSL source");
}
