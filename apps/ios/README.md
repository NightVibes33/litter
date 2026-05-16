# Litter iOS

`apps/ios` contains the primary native iOS app. The Xcode project is generated from `project.yml`; edit `project.yml` and run `make xcgen` instead of hand-editing `Litter.xcodeproj`.

## Main Surfaces

- SwiftUI home dashboard, conversation timeline, settings, appearance/theme controls, wallpaper and typing-effect picker, local file workspace, and settings terminal.
- Local iSH Alpine fakefs runtime rooted at `/root`; `/root/.codex` is bridged to native Codex storage and `/mnt/apps` exposes app-provided files.
- Shared Rust/UniFFI Codex client for local/remote sessions, SSH, Slingshot connected computers, goals, permissions, widgets, and app-server transport.
- Optional native llama runtime for installed `local-gguf:<id>` models.
- Optional private Nyxian BuildKit assets for on-device Swift checks, builds, tests, and unsigned IPA packaging.
- PiP streaming cards, CarPlay voice scene support, and experimental Watch targets.

## BuildKit

The app installs fakefs shims such as `litter-fs-doctor`, `litter-swift-check`, `litter-swift-selftest`, `litter-swift-build`, `litter-swift-test`, `litter-ipa-build`, `litter-build-status`, and compatibility wrappers including `swift`, `swiftc`, `clang`, `ld`, `xcodebuild`, `xcrun`, `plutil`, and `code`.

Full native Swift/iOS compilation requires the private `LitterBuildKitAssets.zip` bundle. That bundle contains `CoreCompiler.framework`, `CoreCompilerSupportLibs`, `LitterBuildKitNative.framework`, and a user-owned iPhoneOS SDK. Apple SDK files and compiled private assets are not committed here.

Important: if `ThirdParty/Nyxian/LitterBuildKitNative/**` changes, rebuild and upload the private BuildKit asset pack before rebuilding the unsigned IPA. The IPA embeds the framework from the asset ZIP; an IPA-only rebuild can reuse a stale native framework.

## Regenerate Project

```bash
make xcgen
```

## Unsigned IPA

Use `.github/workflows/ios-unsigned-ipa.yml` for SideStore/AltStore-style unsigned IPA artifacts. Use `.github/workflows/buildkit-assets.yml` first when the private BuildKit framework or SDK payload must change.
