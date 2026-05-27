# Development Guide

## Product Target

The primary product target is iOS sideloading with unsigned IPA artifacts for SideStore/AltStore-style re-signing. TestFlight and App Store notes are secondary references, not the current core delivery path.

## Litter BuildKit

BuildKit is the Nyxian-backed on-device Swift/iOS build path. The focused BuildKit source import lives under `ThirdParty/Nyxian`; app-visible status is in Settings -> BuildKit; fakefs command shims are installed into `/usr/local/bin` inside iSH. Commands wait for native status/log output by default, can run async with `--no-wait`, and store results under `/root/builds`. Full native Swift compilation requires a private `LitterBuildKitAssets` bundle with CoreCompiler.framework, CoreCompilerSupportLibs, LitterBuildKitNative.framework, and a user-owned iPhoneOS SDK. `litter-nyxian-status` is the quickest bot-readable readiness check because it reports direct Swift execution, unsigned IPA capability, native mode, capabilities, and exact missing requirements.

Use `make nyxian-vendor` on a Mac to refresh the focused upstream Nyxian/LLVM-On-iOS BuildKit source import while preserving Litter's `LitterBuildKitNative` bridge. Use `make nyxian-buildkit-assets` to build/package the private `LitterBuildKitAssets.zip`; the default mode is `inprocess`, which links the Nyxian driver glue into `LitterBuildKitNative.framework`. Use `make nyxian-buildkit-assets-verify` or `tools/scripts/verify-nyxian-buildkit-assets.sh <zip-or-folder>` before uploading. `tools/scripts/upload-buildkit-assets-release.sh` publishes the ZIP and `.sha256` sidecar to the private release consumed by Settings -> BuildKit and CI.

The in-process native bridge stages Swift projects from fakefs into `Documents/BuildKit/Jobs/<job-id>`, uses CoreCompiler/MobileDevelopmentKit for Swift jobs, writes a minimal iOS app bundle, and packages unsigned IPAs without shelling out to `/usr/bin/zip`. If an IPA is produced, the app copies it back to `/root/builds/<job-id>/<App>.ipa` through `IshFS.writeFile` so bots can operate on the artifact from fakefs.

Use `tools/scripts/build-litter-buildkit-native.sh` to build the native wrapper, then `tools/scripts/package-buildkit-assets.sh` on macOS to create that private bundle. Use `LITTER_BUILDKIT_NATIVE_MODE=inprocess` with `CORECOMPILER_FRAMEWORK` for an in-process Nyxian driver, or set `NYXIAN_BUILDKIT_RUNNER` when packaging a separate runner executable. The public workflow stays SDK-clean; private CI may set `LITTER_BUILDKIT_ASSET_URL` and `LITTER_BUILDKIT_ASSET_SHA256` so `apps/ios/scripts/prepare-buildkit-assets.sh` injects assets before Xcode project generation.


## Prerequisites

- **Xcode.app** (full install, not only Command Line Tools):

  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```

- **Rust via rustup** with iOS targets. If Homebrew's `rust` formula is installed, its `cargo`/`rustc` will shadow rustup and break cross-compilation. Either `brew uninstall rust` or ensure `~/.cargo/bin` appears before `/opt/homebrew/bin` in your `PATH`.

  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
  ```

- **meson** + **ninja** (required by `webrtc-audio-processing-sys`):

  ```bash
  brew install meson
  ```

- **xcodegen** (for regenerating `Litter.xcodeproj`):

  ```bash
  brew install xcodegen
  ```

## Connect Your Mac to Litter Over SSH

Use this flow to make Codex sessions from your Mac visible in the iOS app.

1. Enable SSH on the Mac.

   - UI: `System Settings` -> `General` -> `Sharing` -> enable `Remote Login`.
   - CLI:
     ```bash
     sudo systemsetup -setremotelogin on
     ```
   - If you get a Full Disk Access error, grant it to your terminal app in `System Settings` -> `Privacy & Security` -> `Full Disk Access`, then restart terminal and retry.

2. Verify SSH and Codex binaries from a non-interactive SSH shell.

   ```bash
   ssh <mac-user>@<mac-host-or-ip> 'echo ok'
   ssh <mac-user>@<mac-host-or-ip> 'command -v codex || command -v codex-app-server'
   ```

   If the second command prints nothing, install Codex and/or fix shell PATH startup files.

3. Connect from the Litter app.

   - Keep phone and Mac on the same LAN (or same Tailnet).
   - In Discovery: tap a host showing `codex running` to connect directly, or tap an `SSH` host and enter credentials.

4. Fallback: run app-server manually bound to loopback and forward the port over SSH.

   On the Mac:

   ```bash
   codex app-server --listen ws://127.0.0.1:8390
   ```

   Then connect the phone via the `SSH` flow in Discovery — Litter opens the SSH connection, port-forwards `127.0.0.1:8390`, and connects through the tunnel. Do not bind `0.0.0.0` unless you fully understand the exposure; the SSH flow is the supported path.

5. Thread/session listing is `cwd`-scoped. If expected sessions are missing, choose the same working directory used when those sessions were created.

## Codex Submodule + Patches

Upstream Codex is vendored as a submodule at `shared/third_party/codex`.

Current local patch set (applied by `sync-codex.sh`):

- `patches/codex/ios-exec-hook.patch`
- `patches/codex/client-controlled-handoff.patch`
- `patches/codex/mobile-code-mode-stub.patch`

Additional patches (not auto-applied):

- `patches/codex/realtime-transcript-deltas.patch`

Sync/apply (idempotent):

```bash
./apps/ios/scripts/sync-codex.sh
```

Pass `--recorded-gitlink` to reset the submodule to the commit recorded in the superproject.

## Build the Rust Bridge

```bash
./apps/ios/scripts/build-rust.sh              # package mode (device + sim + xcframework)
./apps/ios/scripts/build-rust.sh --fast-device # raw device staticlib only
```

## Build and Run iOS

Regenerate project if `apps/ios/project.yml` changed:

```bash
make xcgen
```

Open in Xcode:

```bash
open apps/ios/Litter.xcodeproj
```

CLI build:

```bash
xcodebuild -project apps/ios/Litter.xcodeproj -scheme Litter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```


## TestFlight (iOS)

1. Authenticate with App Store Connect:

   ```bash
   asc auth login \
     --name "Litter ASC" \
     --key-id "<KEY_ID>" \
     --issuer-id "<ISSUER_ID>" \
     --private-key "$HOME/AppStore.p8" \
     --network
   ```

2. Bootstrap TestFlight defaults:

   ```bash
   APP_BUNDLE_ID=<BUNDLE_ID> ./apps/ios/scripts/testflight-setup.sh
   ```

3. Build and upload:

   ```bash
   APP_BUNDLE_ID=<BUNDLE_ID> \
   APP_STORE_APP_ID=<APP_STORE_CONNECT_APP_ID> \
   TEAM_ID=<APPLE_TEAM_ID> \
   ASC_KEY_ID=<KEY_ID> \
   ASC_ISSUER_ID=<ISSUER_ID> \
   ASC_PRIVATE_KEY_PATH="$HOME/AppStore.p8" \
   ./apps/ios/scripts/testflight-upload.sh
   ```

   - Reads `MARKETING_VERSION` from `apps/ios/project.yml`; auto-bumps patch if the version is already live.
   - Auto-increments build number from the latest App Store Connect build.

## App Store Release (iOS)

```bash
APP_BUNDLE_ID=<BUNDLE_ID> \
APP_STORE_APP_ID=<APP_STORE_CONNECT_APP_ID> \
TEAM_ID=<APPLE_TEAM_ID> \
ASC_KEY_ID=<KEY_ID> \
ASC_ISSUER_ID=<ISSUER_ID> \
ASC_PRIVATE_KEY_PATH="$HOME/AppStore.p8" \
./apps/ios/scripts/app-store-release.sh
```

Metadata is sourced from `apps/ios/fastlane/metadata/en-US/`.
