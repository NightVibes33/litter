// jkcoxson

extern crate bindgen;

use std::{env, fs::canonicalize, path::PathBuf};

fn main() {
    // Tell cargo to invalidate the built crate whenever build files change
    println!("cargo:rerun-if-changed=wrapper.h");
    println!("cargo:rerun-if-changed=build.rs");

    ////////////////////////////
    //   BINDGEN GENERATION   //
    ////////////////////////////

    if cfg!(feature = "pls-generate") {
        // Get gnutls path per OS
        let gnutls_path = match env::consts::OS {
            "linux" => "/usr/include",
            "macos" => "/opt/homebrew/include",
            "windows" => {
                panic!("Generating bindings on Windows is broken, pls remove the pls-generate feature.");
            }
            _ => panic!("Unsupported OS"),
        };

        let bindings = bindgen::Builder::default()
            // The input header we would like to generate
            // bindings for.
            .header("wrapper.h")
            // Include in clang build
            .clang_arg(format!("-I{}", gnutls_path))
            // Tell cargo to invalidate the built crate whenever any of the
            // included header files changed.
            .parse_callbacks(Box::new(bindgen::CargoCallbacks))
            // Finish the builder and generate the bindings.
            .generate()
            // Unwrap the Result and panic on failure.
            .expect("Unable to generate bindings");

        // Write the bindings to the $OUT_DIR/bindings.rs file.
        let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
        bindings
            .write_to_file(out_path.join("bindings.rs"))
            .expect("Couldn't write bindings!");
    }

    if cfg!(feature = "vendored") {
        // Change current directory to OUT_DIR
        let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
        env::set_current_dir(out_path).unwrap();
        // Clone the vendored libraries
        repo_setup("https://github.com/libimobiledevice/libplist.git");

        // Build libplist for the Cargo target. The upstream build script lets
        // autotools guess the host from `clang`; iOS cross-builds need it set.
        let mut config = autotools::Config::new("libplist");
        config.without("cython", None);
        configure_for_target(&mut config);
        config.cflag("-std=gnu17");
        let dst = config.build();

        println!(
            "cargo:rustc-link-search=native={}",
            dst.join("lib").display()
        );

        println!("cargo:rustc-link-lib=static=plist-2.0");
    } else {
        // Check if folder ./override exists
        let override_path = PathBuf::from("./override").join(env::var("TARGET").unwrap());
        if override_path.exists() {
            println!(
                "cargo:rustc-link-search={}",
                canonicalize(&override_path).unwrap().display()
            );
        }

        println!("cargo:rustc-link-search=/usr/local/lib");
        println!("cargo:rustc-link-search=/usr/lib");
        println!("cargo:rustc-link-search=/opt/homebrew/lib");
        println!("cargo:rustc-link-search=/usr/local/opt/libimobiledevice/lib");
        println!("cargo:rustc-link-search=/usr/local/opt/libusbmuxd/lib");
        println!("cargo:rustc-link-search=/usr/local/opt/libimobiledevice-glue/lib");
    }
}

fn configure_for_target(config: &mut autotools::Config) {
    let target = env::var("TARGET").unwrap_or_default();
    let Some(host) = autotools_host_for_target(&target) else {
        return;
    };

    env::set_var("PKG_CONFIG_ALLOW_CROSS", "1");
    config.config_option("host", Some(host));
}

fn autotools_host_for_target(target: &str) -> Option<&'static str> {
    match target {
        "aarch64-apple-ios" | "aarch64-apple-ios-sim" => Some("aarch64-apple-darwin"),
        "x86_64-apple-ios" => Some("x86_64-apple-darwin"),
        _ => None,
    }
}

fn repo_setup(url: &str) {
    let mut cmd = std::process::Command::new("git");
    cmd.arg("clone");
    cmd.arg("--depth=1");
    cmd.arg(url);
    cmd.output().unwrap();
    env::set_current_dir(url.split('/').last().unwrap().replace(".git", "")).unwrap();
    env::set_var("NOCONFIGURE", "1");
    let mut cmd = std::process::Command::new("./autogen.sh");
    let _ = cmd.output();
    env::remove_var("NOCONFIGURE");
    env::set_current_dir("..").unwrap();
}
