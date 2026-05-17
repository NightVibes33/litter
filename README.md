# Litter

<p align="center">
  <img src="apps/ios/Sources/Litter/Resources/brand_logo.png" alt="Litter logo" width="180" />
</p>

<p align="center">
  Native iOS Codex client with a Rust bridge, local iSH runtime, remote computer connections, and an experimental on-device Swift BuildKit.
</p>

<p align="center">
  <a href="https://kittylitter.app"><img src="docs/badges/website.svg" alt="kittylitter.app" /></a>
  &nbsp;
  <a href="https://apps.apple.com/us/app/kittylitter/id6759521788"><img src="docs/badges/app-store.svg" alt="App Store" /></a>
</p>

## Current Scope

Litter is a native SwiftUI iOS app that talks to Codex through a shared Rust client. It can run a local Codex runtime inside an embedded iSH Alpine Linux fakefs, connect to remote Codex app servers, pair with connected computers through Slingshot, and route conversations through hosted ChatGPT, OpenAI-compatible computer/LAN endpoints, or installed on-device GGUF models when the native llama runtime is present.

The repository also contains CI release lanes for iOS, TestFlight, Mac Catalyst, and a private BuildKit asset pipeline for on-device Swift/iOS builds.

Developer: [NightVibes33](https://github.com/NightVibes33).

## Screenshots

<p align="center">
  <img src="docs/screenshots/01-hero-iphone-1320x2868.png" alt="Home" width="200" />
  <img src="docs/screenshots/02-remote-iphone-1320x2868.png" alt="Remote servers" width="200" />
  <img src="docs/screenshots/07-generative-ui-iphone-1320x2868.png" alt="Generative UI" width="200" />
  <img src="docs/screenshots/05-realtime-voice-iphone-1320x2868.png" alt="Realtime voice" width="200" />
</p>

## Repository Layout

```text
apps/ios/                  Primary SwiftUI app. project.yml is the XcodeGen source of truth.
shared/rust-bridge/        Shared Rust mobile client, UniFFI surface, iSH runtime, SSH, Slingshot, app-server transport.
shared/third_party/codex/  Upstream Codex submodule used by the Rust bridge.
patches/codex/             Local Codex patches applied during sync/build.
ThirdParty/Nyxian/         Focused Nyxian/CoreCompiler/LLVM-On-iOS source import for BuildKit.
tools/scripts/             Build, packaging, BuildKit asset, release, and verification scripts.
docs/                      Development, release, architecture, badge, and screenshot docs.
.github/workflows/         CI for unsigned IPA, BuildKit assets, mobile release, TestFlight, and Mac.
```

Tracked source currently includes Swift, Rust, Objective-C/C/C++, shell scripts, XcodeGen config, GitHub Actions workflows, and vendored third-party source needed by the iOS runtime.

## Quick Start

On macOS with Xcode, Rust, XcodeGen, and the expected mobile toolchains installed:

```bash
make ios-device-fast   # fast iOS device build
make ios-sim-fast      # fast iOS simulator build
make rust-check        # host cargo check for shared Rust crates
make rust-test         # host cargo test for shared Rust crates
```

`apps/ios/project.yml` is the source of truth for `apps/ios/Litter.xcodeproj`:

```bash
make xcgen
```

The iOS app target deploys to iOS 18.0 and is built by CI with the iOS 26 SDK lane on `macos-26` / Xcode 26.3. The Swift package manifest exists for package consumers, but normal app builds should use XcodeGen and the Make targets.

## Architecture

Litter's iOS UI is SwiftUI. The app shell owns platform UI, settings, file import/export, local previews, Keychain-facing credential flows, PiP, CarPlay, Watch surfaces, and native frameworks. The shared Rust crate `codex-mobile-client` owns the Codex app-server protocol, session hydration, Slingshot pairing, SSH bridge logic, remote path handling, saved apps/widgets, permission state, iSH exec integration, and the UniFFI API consumed by Swift.

The local iOS runtime is not the iOS host shell. Commands run inside an embedded persistent iSH Alpine Linux fakefs. The default home is `/root`; Litter creates `/root/litter`, `/root/.litter/builds`, and `/usr/local/bin`; app Documents can be bridged through `/mnt/apps`; and native Codex settings are bridged to `/root/.codex` so local Codex skills can be installed where the app runtime reads them.

A native preflight runs `true` before exposing shell tools. If that fails, the issue is the iSH/runtime bridge, not Swift, BuildKit, PATH, or fakefs command shims.

## Main iOS Features

- Home dashboard with local and remote sessions, active turn state, branching/fork actions, hide/delete/rename actions, zoomed session telemetry, goal banners, and recent activity.
- Conversation timeline with markdown, tool cards, command output display preferences, image generation result cards, selectable/copyable messages, edit/fork actions, streaming assistant rendering, and dynamic widget rendering.
- Discovery and connection flows for local runtime, manual app-server URLs, SSH bootstrapping, LAN/remote servers, and Slingshot connected computers from the signed-in ChatGPT account.
- Settings sections for appearance, font, conversation display, local terminal, experimental features, AI providers, diagnostics bundles, account/API key/base URL, connected servers, and developer BuildKit controls.
- Picture-in-Picture streaming cards using `AVPictureInPictureController` with a sample-buffer SwiftUI renderer.
- CarPlay voice scene support and experimental Apple Watch projection/complication targets.

## File Workspace and Terminal

The Files button opens a local iSH file workspace rooted at `/root`. The browser reads the fakefs through `ishRun`, so it sees the same files the bot and terminal see. It supports:

- List and grid views, breadcrumbs, search, sorting, filters, hidden-file toggles, advanced locations, favorites, recents, and quick locations such as `/root`, `/root/litter`, `/root/.codex`, `/root/.litter/builds`, `/tmp`, and `/usr/local/bin`.
- Creating, renaming, moving, duplicating, deleting, making executable, sharing, compressing, and extracting files/folders.
- File/folder import from iOS Files, text/code editing, previews, inspector sheets, symlink details, archive/build-artifact detection, and bot-context path copying.
- BuildKit shortcuts for Swift check, Swift build, IPA build, build status, filesystem doctor, and `LitterBuild.json` creation.

The interactive terminal now lives in Settings under `Local Tools -> Terminal`. File browser actions such as `Open Terminal Here` open that shared terminal at the selected fakefs directory. This terminal uses the same iSH runtime and command shims used by Codex tool calls.

## Appearance, Wallpapers, and Typing Effects

Appearance settings include system/light/dark mode selection, app-wide conversation font scaling, live preview, and separate light/dark theme pickers loaded from the app's theme resources.

Conversation wallpaper settings are scoped per thread or per server. The background tab supports built-in generated presets, light/dark app themes as backgrounds, solid colors, images from Photos, videos from Photos, and video URLs. Custom image preview uses a fitted image renderer instead of blindly zooming the image to fill the screen.

Built-in background presets in `WallpaperManager` are:

- Aurora
- Terminal Grid
- Blueprint
- Midnight Neon
- Ocean Glass
- Sakura
- Carbon Mesh
- Solar Flare
- Paper
- Forest

Typing effects are persisted with the same wallpaper scope and are driven by `StreamingEffectKind` plus HairballUI `StreamingTextEffect` implementations. Current options are:

- Fade Edge
- Sparkle
- Glow Cursor
- Wave
- Scale Pop
- Rainbow
- Fire Trail
- Explosion
- Nyan Cat
- Matrix Decode
- Phosphor CRT
- Shockwave
- Typewriter
- Terminal Scan
- Soft Blur
- Neon Pulse
- Ghost Trail
- Pixel Decode
- Ink Spread
- Slide Up
- Glitch
- Focus Beam

The typing effect tab also exposes reveal speed, reveal granularity, and reveal mode controls.

## AI Providers and Local Models

The runtime picker separates three routes:

- ChatGPT Account: the signed-in local Codex/ChatGPT route.
- Computer Bridge: a selected Mac/Windows/Linux Codex app-server bridge.
- On-device Model: installed `local-gguf:<id>` models backed by the native llama runtime when `apps/ios/Frameworks/llama.xcframework` is available.

AI provider settings include hosted/OpenAI-compatible routing, local GGUF catalog/import/download flows, runtime settings, cellular policy, thermal/storage/RAM guidance, idle unload behavior, post-download validation, and per-model generation options. Local GGUF turns currently support text and absolute fakefs file mentions; plugin mentions and broader hosted-tool behavior should use hosted or bridge routes.

The unsigned iOS build lane compiles a TurboQuant-flavored llama.cpp XCFramework when the cache is missing and records the resolved framework version in `apps/ios/Frameworks/llama.version`. TurboQuant options are exposed only when the linked runtime reports support for them.

## Thread Goals

The Rust bridge advertises `features.goals` and includes UniFFI methods for getting, setting, clearing, and hydrating thread goals. iOS stores hydrated goals in app state and renders goal status/objective/usage in the home dashboard and PiP views. Goal persistence depends on the connected Codex server's state database being available for that thread.

## On-device Swift BuildKit

Litter vendors Nyxian source as the foundation for its on-device iOS toolchain, then layers a Litter-specific native BuildKit bridge on top. The public repo contains source and reproducible vendor/build scripts; full on-device Swift/iOS compilation still requires a private `LitterBuildKitAssets` bundle because Apple SDK files and compiled private frameworks are not committed.

The vendored Nyxian source is pinned in `ThirdParty/Nyxian/LITTER_NYXIAN_IMPORT.json` and verified by `tools/scripts/verify-nyxian-source-import.sh`. The private asset bundle must include:

- `Toolchains/Nyxian/CoreCompiler.framework`
- `Toolchains/Nyxian/CoreCompilerSupportLibs`
- `Toolchains/Nyxian/LitterBuildKitNative.framework`
- `SDK/iPhoneOS<version>.sdk`
- optional `Toolchains/Nyxian/bin/litter-buildkit-runner` for runner mode
- `manifest.json` with required paths and SHA256 entries

The important packaging rule is this: changing `ThirdParty/Nyxian/LitterBuildKitNative/**` is not enough by itself. The app loads `LitterBuildKitNative.framework` from `LitterBuildKitAssets.zip`. After native bridge changes, rebuild and upload the private BuildKit asset pack first, then rebuild the unsigned IPA against the new asset SHA. Rebuilding only the IPA can reuse a stale private framework and leave the runtime behavior unchanged.

Canonical fakefs commands installed into `/usr/local/bin` include:

```text
litter-buildkit
litter-nyxian-status
litter-buildkit-install-assets
litter-fs-doctor
litter-env-report
litter-dev-bootstrap
litter-swift-check
litter-swift-selftest
litter-swiftc
litter-swift-build
litter-swift-test
litter-ipa-build
litter-ipa-package
litter-clang
litter-ld
litter-build-status
litter-build-cancel
```

Compatibility shims are also installed for common bot expectations:

```text
swift swiftc clang clang++ cc c++ ld ld64 xcodebuild xcrun plutil code
ar llvm-ar ranlib llvm-ranlib nm llvm-nm objdump llvm-objdump strip strings lipo
```

`litter-*` commands are the canonical API. The compatibility shims support the iOS-only cases Litter can actually run. This is not full desktop Xcode: SwiftPM package resolution, simulator workflows, Interface Builder, previews, signing/provisioning management, and macOS toolchains are outside BuildKit v1.

Useful in-app/fakefs checks:

```bash
litter-fs-doctor
litter-build-status
litter-nyxian-status
litter-swift-selftest
printf 'print("Swift is running on device")\n' > /root/hello.swift
litter-swift-check /root/hello.swift
swiftc /root/hello.swift -o /root/hello
```

## BuildKit Asset and IPA CI Flow

`.github/workflows/buildkit-assets.yml` builds the private asset pack on `macos-26`, verifies it, uploads it to the private release repo, updates the unsigned IPA workflow secrets, and can dispatch a new unsigned IPA build. Its default release target is `NightVibes33/litter-buildkit-assets` with tag `buildkit-ios26.4-v1`.

Use this flow when BuildKit source or private framework behavior changes:

1. Run `Build Private BuildKit Assets` on the branch containing the source fix.
2. Use `force_rebuild=true` when the native framework must be rebuilt. Set `use_existing_private_release=false` if you need to guarantee the old release asset is not reused.
3. Let the workflow upload a new `LitterBuildKitAssets.zip` and update `LITTER_BUILDKIT_ASSET_URL` plus `LITTER_BUILDKIT_ASSET_SHA256`.
4. Run or let it dispatch `.github/workflows/ios-unsigned-ipa.yml` on the same branch.
5. Install the new IPA and run `litter-swift-selftest` inside Litter.

`.github/workflows/ios-unsigned-ipa.yml` builds a SideStore/AltStore-style unsigned IPA artifact named `Litter-iOS26-Unsigned-SideStore-AltStore.ipa`. It downloads and verifies the private BuildKit assets when the asset secrets are set, packages `LitterBuildKitAssets.zip` into the app resources, embeds the loadable compiler frameworks/support dylibs under `Payload/*.app/Frameworks`, and publishes both Actions artifacts and GitHub Release assets. The IPA is intentionally unsigned and must be re-signed by a sideloading tool before installation.

## Local Runtime Notes

- Local commands run inside iSH Alpine Linux, not the iOS host filesystem.
- The fakefs can see `/root`, `/tmp`, `/usr/local/bin`, `/root/.codex`, `/root/litter`, and app-provided mounts such as `/mnt/apps`.
- It cannot directly see arbitrary iOS sandbox paths like `/private/var/mobile/...`; Litter stages files through Documents/BuildKit when native code must read them.
- `litter-dev-bootstrap` repairs/installs expected fakefs utilities where possible; some tools may still be absent until Alpine packages are installed.
- Shell failures with exit `-6` mean the iSH runtime was not bootstrapped, so debugging should start at runtime/session initialization before looking at PATH, Swift, or BuildKit.

## Make Targets

| Target | Description |
|---|---|
| `make ios-device-fast` | Fast iOS device build using the raw device staticlib lane. |
| `make ios-sim-fast` | Fast iOS simulator build. |
| `make ios` | Full iOS package lane. |
| `make rust-check` | Host `cargo check` for shared Rust crates. |
| `make rust-test` | Host `cargo test` for shared Rust crates. |
| `make bindings` | Regenerate UniFFI Swift bindings. |
| `make xcgen` | Regenerate `Litter.xcodeproj` from `apps/ios/project.yml`. |
| `make alpine-fs` | Prepare the bundled Alpine fakefs. |
| `make llama-ios` | Build the iOS llama.cpp/TurboQuant XCFramework. |
| `make nyxian-source-verify` | Verify the committed Nyxian source import. |
| `make nyxian-buildkit-assets` | Build/package private BuildKit assets on macOS. |
| `make nyxian-buildkit-assets-verify` | Validate a BuildKit asset ZIP or folder. |
| `make clean` | Remove build artifacts. |

## Contributing

Litter is under active development. Small, focused PRs are easier to review than broad rewrites because the app, Rust bridge, and private BuildKit pipeline are tightly coupled. See `CONTRIBUTING.md` for contributor expectations.

## License

Litter is licensed under GPLv3 with an additional GPLv3 section 7 permission for Apple App Store and iOS distribution. Vendored Nyxian source is AGPL-3.0-or-later; see `ThirdParty/Nyxian/LICENSE` and `THIRD_PARTY_NOTICES.md`.
