# iOS Rust ABI compile check

This standalone package compiles the pure Rust Apple ABI dependency paths used
by the mobile graph, without requiring Xcode or linking a final app. Rustix 1.x
enables every API to exercise platform gates; legacy Rustix and both Nix versions
retain the features selected by the iOS graph. It also checks the local
num_threads compatibility source against the same libc version.

After installing that Rust target, run:

```sh
cargo check --locked --manifest-path tools/rust-ios-compat-check/Cargo.toml --target aarch64-apple-ios
```

Rust CI compares
these dependency pins with the actual iOS metadata graph before compiling.
Update the checker and its lockfile together with mobile dependency changes.

This check catches target-specific Rust errors early. The full iOS SDK build,
archive, and packaging still need to pass before an IPA is usable.
