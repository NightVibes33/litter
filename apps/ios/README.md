# Litter iOS

`apps/ios` contains the primary native iOS app. The Xcode project is generated from `project.yml`; edit `project.yml` and run `make xcgen` instead of hand-editing `Litter.xcodeproj`.

## Main Surfaces

- SwiftUI home dashboard, conversation timeline, settings, appearance/theme controls, wallpaper and typing-effect picker, local file workspace, and settings terminal.
- Local iSH Alpine fakefs runtime rooted at `/root`; `/root/.codex` is bridged to native Codex storage, `/mnt/apps` exposes app-provided files, and `/mnt/container` exposes the native app container for diagnostics and storage inspection.
- Shared Rust/UniFFI Codex client for local/remote sessions, SSH, Slingshot connected computers, goals, permissions, widgets, and app-server transport.
- Embedded KittyStore surface based on SideStore/AltStore with SideStore-style News, Sources, Browse, My Apps, and Settings tabs, plus Feather-style signing inputs.
- Directly vendored emexDE integration for on-device Swift checks, builds, tests, and unsigned IPA packaging work.
- PiP streaming cards, CarPlay voice scene support, and experimental Watch targets.

## emexDE integration

The app installs fakefs shims such as `litter-fs-doctor`, `litter-swift-check`, `litter-swift-selftest`, `litter-swift-build`, `litter-swift-test`, `litter-ipa-build`, `litter-build-status`, and compatibility wrappers including `swift`, `swiftc`, `clang`, `ld`, `xcodebuild`, `xcrun`, `plutil`, and `code`.

Alley Cat now vendors the upstream emexDE source tree directly under `ThirdParty/EmexDE`. The app target and the `CoreCompiler`, `MobileDevelopmentKit`, `emexDE`, and `LiveProcess` targets build directly against files in `ThirdParty/EmexDE/Source`, and the repo also keeps a fuller upstream mirror snapshot under `ThirdParty/EmexDE/_upstream_full` for direct-file auditing and recovery.

Opening emexDE from the app no longer depends on downloading or installing a private `LitterBuildKitAssets.zip` bundle first. The emexDE route is opened directly from the bundled app experience, and upstream emexDE source trees are embedded into the app bundle during iOS builds.

Unsigned IPA packaging still does not need a signing certificate. Original Nyxian run/install mode still does: the installed Litter app must be signed by SideStore, AltStore, Feather, or another signer, and Settings > Signing must import the matching `.p12` certificate so built apps can be signed with the same identity. Imported developer certificates are validated for PKCS#12 password/private-key usability and optional provisioning-profile match; they do not need to pass iOS system trust.

Important: this repo now treats direct emexDE vendoring as the source of truth. If upstream emexDE changes, refresh `ThirdParty/EmexDE/_upstream_full` and the corresponding `ThirdParty/EmexDE/Source` directories instead of relying on a private BuildKit asset release.

## Regenerate Project

```bash
make xcgen
```

## Unsigned IPA

Use `.github/workflows/ios-unsigned-ipa.yml` for SideStore/AltStore-style unsigned IPA artifacts. Dispatch it manually with `build_mode=fast-device` for the launch-safe public lane built around the directly vendored emexDE integration path. Refresh the vendored `ThirdParty/EmexDE` trees when upstream emexDE payloads change.
