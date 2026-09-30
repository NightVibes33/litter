//! Pinned C sources shared by KittyStore's vendored native build scripts.
use std::path::Path;
use std::process::Command;

pub const DEPENDENCIES: &[(&str, &str)] = &[
    ("https://github.com/libimobiledevice/libplist.git", "fe3dc34dc3484006e12b403f7ceb06f0ad40b6f4"),
    ("https://github.com/libimobiledevice/libimobiledevice-glue.git", "da770a7687f35fbb981db4d7b47b1b032cd5c2c7"),
    ("https://github.com/libimobiledevice/libtatsu.git", "e7d6ad13ef928aa609d0ccdfc586f7d6e8e049bf"),
    ("https://github.com/libimobiledevice/libusbmuxd.git", "93eb168bf6b07472d17781328c21df0c60300524"),
    ("https://github.com/libimobiledevice/libimobiledevice.git", "fa0f79190142bc309307967c058f89c1b36eb6b8"),
];

fn checked(command: &mut Command, operation: &str) {
    let status = command.status().unwrap_or_else(|error| panic!("{operation}: {error}"));
    assert!(status.success(), "{operation} failed: {status}");
}

pub fn prepare_source(url: &str, revision: &str, destination: &Path) {
    assert!(revision.len() == 40 && revision.bytes().all(|c| c.is_ascii_hexdigit()),
            "native source revision must be a full commit SHA");
    if !destination.join(".git").exists() {
        checked(Command::new("git").args(["clone", "--no-checkout", "--depth=1", url])
                .arg(destination), "clone pinned native dependency");
    }
    checked(Command::new("git").arg("-C").arg(destination)
            .args(["fetch", "--depth=1", "origin", revision]), "fetch pinned native dependency");
    checked(Command::new("git").arg("-C").arg(destination)
            .args(["checkout", "--detach", revision]), "checkout pinned native dependency");
    let actual = Command::new("git").arg("-C").arg(destination)
        .args(["rev-parse", "HEAD"]).output().expect("read native dependency revision");
    assert!(actual.status.success(), "could not read native dependency revision");
    assert_eq!(String::from_utf8(actual.stdout).expect("UTF-8 revision").trim(), revision);
    checked(Command::new("./autogen.sh").current_dir(destination).env("NOCONFIGURE", "1"),
            "prepare pinned native dependency with autogen.sh");
}

pub fn repo_setup(url: &str) {
    let revision = DEPENDENCIES.iter().find(|entry| entry.0 == url)
        .map(|entry| entry.1).unwrap_or_else(|| panic!("unrecorded native dependency: {url}"));
    let name = url.rsplit('/').next().expect("repository name").trim_end_matches(".git");
    let manifest = std::env::var_os("CARGO_MANIFEST_DIR").expect("native Cargo manifest directory");
    let side_store = Path::new(&manifest).parent().expect("SideStore source root");
    let snapshot = side_store.join("NativeDependencies").join(name);
    assert!(snapshot.join(".git").exists(),
            "missing pinned native source {}; run git submodule update --init --recursive", snapshot.display());
    let actual = Command::new("git").arg("-C").arg(&snapshot)
        .args(["rev-parse", "HEAD"]).output().expect("read native source gitlink");
    assert!(actual.status.success(), "could not read native source gitlink");
    assert_eq!(String::from_utf8(actual.stdout).expect("UTF-8 revision").trim(), revision,
               "native source checkout does not match NATIVE_DEPENDENCIES.json");
    prepare_source(snapshot.to_str().expect("UTF-8 source path"), revision, Path::new(name));
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn exact_checkout_and_autogen_failures_are_verified() {
        let root = std::env::temp_dir().join(format!("litter-native-pins-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let source = root.join("source");
        std::fs::create_dir_all(&source).unwrap();
        checked(Command::new("git").arg("init").arg(&source), "initialize test source");
        let script = source.join("autogen.sh");
        std::fs::write(&script, "#!/bin/sh\ntest \"$NOCONFIGURE\" = 1\n").unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        checked(Command::new("git").arg("-C").arg(&source).args(["add", "."]), "add test source");
        checked(Command::new("git").arg("-C").arg(&source)
            .args(["-c", "user.name=Test", "-c", "user.email=test@example.com",
                   "-c", "commit.gpgsign=false", "commit", "-m", "native source"]), "commit test source");
        let revision = Command::new("git").arg("-C").arg(&source).args(["rev-parse", "HEAD"])
            .output().unwrap();
        let revision = String::from_utf8(revision.stdout).unwrap();
        let destination = root.join("checkout");
        prepare_source(source.to_str().unwrap(), revision.trim(), &destination);
        std::fs::write(destination.join("autogen.sh"), "#!/bin/sh\nexit 7\n").unwrap();
        assert!(std::panic::catch_unwind(|| {
            prepare_source(source.to_str().unwrap(), revision.trim(), &destination);
        }).is_err());
        assert!(std::panic::catch_unwind(|| {
            prepare_source(source.to_str().unwrap(), "main", &destination);
        }).is_err());
        std::fs::remove_dir_all(root).unwrap();
    }
}
