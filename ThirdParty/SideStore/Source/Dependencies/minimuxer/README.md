# minimuxer

minimuxer is the lockdown muxer used by [SideStore](https://github.com/SideStore/SideStore). It runs on device through [em_proxy](https://github.com/SideStore/em_proxy).

![Alt](https://repobeats.axiom.co/api/embed/95df7af50adae86935e34bc1f59083f1db326c24.svg "Repobeats analytics image")

## Architecture

```
Sources/                    ← Main Minimuxer Swift API
RustBridge/
  src/                      ← Low level rust bridge
  MinimuxerBridge.swift     ← Swift ↔ Rust FFI layer using @_silgen_name
  lib/
    RustBridge.xcframework  ← Pre-built RustBridge xcframework used by MinimuxerBridge
  Makefile                  ← Manually Build RustBridge and produce xcframework
```

## Building

```bash
cd RustBridge

make build        # compile Rust bridge static libs for iOS, iOS Simulator, macOS
make xcframework  # create RustBridge/lib/RustBridge.xcframework (contains all platforms)
```

After creating the `RustBridge.xcframework` manually check-in if required

### When to rebuild

Any changes to files under `RustBridge/src/**` will require recreating the RustBridge.xcframework

### Verify the build

After running `make xcframework`, confirm SPM package build works using the following

```bash
cd ..
swift build
```

## Development

### Off device

While minimuxer is built to run on device, it is recommended to test from your computer through USB to speed up the development process. (Obviously, you should still test on device; see
[On device](#on-device) for more info)

```bash
cargo test <test function name> -- --nocapture
```

to run it. (`-- --nocapture` allows for logs to be shown, which are essential for debugging)

Filter to only minimuxer logs:

```bash
cargo test <test function name> -- --nocapture 2>&1 | grep -e minimuxer:: -e tests.rs
```

After implementing your feature, you should also run

```bash
cargo clippy --no-deps
```

to lint your code.

If you want some of the lints to auto fix, you can use

```bash
cargo clippy --no-deps --fix
```

> Note: tests currently don't automatically mount the developer disk image. You must do that yourself with `ideviceimagemounter` or via SideStore on device.

### On device

`MinimuxerBridge.swift` exposes the Rust functions to Swift using `@_silgen_name` — no C headers or code generation required. When adding a new Rust function:

1. Add the `#[no_mangle] pub extern "C"` function in `RustBridge/src/bridge.rs`
2. Add the corresponding `@_silgen_name` declaration + Swift wrapper in `MinimuxerBridge.swift`
3. Run `make xcframework` and commit the updated xcframework

## Developer Notes

Unless otherwise stated, references to AltServer implementations are referring to `AltServer/Devices/ALTDeviceManager.mm`

### Adding a swift-bridge/ffi function

Once you've made your function, added it to the tests and verified that it works, you can add it to swift-bridge/ffi to allow Swift to use it.

1. Import your function in the `ffi imports` section of `lib.rs`
2. In `mod ffi` -> `extern "Rust"`, add your function to the section for the file you added it to.

### Returning a Result from a swift-bridge/ffi function

When making your function, you might have something similar to this:

```rs
pub fn install_provisioning_profile(profile: &[u8]) -> Result<()> { ... }
```

You can `use crate::Res` as a shorthand to `Result<T, crate::Errors>`. (Most files already `use` this)

When exposing your function to the `ffi` module, we unfortunately can't use the `crate::Res` type alias. Instead, do this:
`Result<[the type your function returns. in the case of install_provisioning_profile, it is ()], Errors>`

### `minimuxer_install_provisioning_profile`

AltServer implementation: search `installProvisioningProfiles` and `installProvisioningProfile:(`
