# Litter

<p align="center">
  <img src="apps/ios/Sources/Litter/Resources/brand_logo.png" alt="Litter logo" width="180" />
</p>

<p align="center">
  Native iOS Codex client with a Rust bridge, an embedded iSH runtime, remote computer connections, and an experimental Nyxian-based Swift BuildKit.
</p>

<p align="center">
  <a href="https://kittylitter.app"><img src="docs/badges/website.svg" alt="kittylitter.app" /></a>
  &nbsp;
  <a href="https://apps.apple.com/us/app/kittylitter/id6759521788"><img src="docs/badges/app-store.svg" alt="App Store" /></a>
</p>

## Current Scope

Litter is a SwiftUI iOS app that talks to Codex through `shared/rust-bridge`. It can run Codex commands inside an embedded iSH Alpine Linux fakefs, connect to Codex app servers on other computers, pair through Slingshot, and route chat through a signed-in ChatGPT account or OpenAI-compatible servers such as Ollama or LM Studio running on a computer.

iPhone-local model downloading and inference are not part of the app. Private or local models should run on a computer and be added through the AI Providers screen as an OpenAI-compatible `/v1` endpoint.

The repository also contains CI lanes for unsigned sideload IPAs, TestFlight, Mac Catalyst, and a private BuildKit asset pipeline. Public source contains the Nyxian and BuildKit integration code, but the Apple SDK payload and compiled private BuildKit frameworks are not committed.

Original creator/upstream maintainer: [Daniel Nakov / dnakov](https://github.com/dnakov). This fork is maintained by [NightVibes33](https://github.com/NightVibes33). In this repo, NightVibes, NightVibes33, NightVibes3, ZYN, and Zyn refer to the same fork maintainer, not separate contributors. Accepted upstream contributors and third-party attribution are tracked in [AUTHORS.md](AUTHORS.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Screenshots

<p align="center">
  <img src="docs/screenshots/01-hero-iphone-1320x2868.png" alt="Home" width="200" />
  <img src="docs/screenshots/02-remote-iphone-1320x2868.png" alt="Remote servers" width="200" />
  <img src="docs/screenshots/07-generative-ui-iphone-1320x2868.png" alt="Generative UI" width="200" />
  <img src="docs/screenshots/05-realtime-voice-iphone-1320x2868.png" alt="Realtime voice" width="200" />
</p>

## Repository Layout

```text
apps/ios/                  SwiftUI app. project.yml is the XcodeGen source of truth.
shared/rust-bridge/        Rust mobile bridge, UniFFI API, iSH runtime, SSH, Slingshot, and app-server transport.
shared/third_party/codex/  Upstream Codex submodule used by the bridge.
patches/codex/             Local Codex patches applied during sync/build.
ThirdParty/Nyxian/         Nyxian/CoreCompiler/LLVM-On-iOS source used by BuildKit.
tools/scripts/             Build, release, BuildKit asset, and verification scripts.
docs/                      Development notes, screenshots, badges, and release docs.
.github/workflows/         Unsigned IPA, BuildKit asset, mobile release, TestFlight, and Mac CI.
```

Tracked source includes Swift, Rust, Objective-C/C/C++, shell scripts, XcodeGen config, GitHub Actions workflows, and vendored source needed by the mobile runtime.

## Quick Start

On macOS, install Xcode, Rust, XcodeGen, and the expected mobile toolchains, then use the Make targets:

```bash
make ios-device-fast   # fast iOS device build
make ios-sim-fast      # fast simulator build
make rust-check        # host cargo check for shared Rust crates
make rust-test         # host cargo test for shared Rust crates
```

`apps/ios/project.yml` drives the checked-in Xcode project:

```bash
make xcgen
```

The iOS app target deploys to iOS 18.0. The unsigned IPA workflow runs on `macos-26` with Xcode 26.3. The private BuildKit asset workflow defaults to Xcode 26.4 and Swift `swift-6.3.1-RELEASE`.

## Architecture

The SwiftUI app owns the native interface: home, conversations, settings, file workspace, terminal panel, account and Keychain flows, PiP, CarPlay, Watch surfaces, and BuildKit controls. The Rust bridge owns Codex app-server communication, session hydration, Slingshot pairing, SSH bridge behavior, remote path handling, saved apps/widgets, permission state, iSH command execution, and the UniFFI surface consumed by Swift.

The local runtime is not the iOS host shell. Commands run inside an embedded persistent iSH Alpine Linux fakefs. The default home is `/root`; Litter creates `/root/litter`, `/root/.litter/builds`, and `/usr/local/bin`; app Documents can be bridged through `/mnt/apps`; and Codex home is bridged to `/root/.codex` so installed skills are visible to the app runtime.

Before exposing local shell tools, Litter runs a native preflight command. If simple commands such as `true`, `pwd`, or `ls` fail with bootstrap errors, debug the iSH runtime bridge first. PATH, Swift, and BuildKit checks come after the fakefs is bootstrapped.

## Main iOS Features

- Home dashboard for local and remote sessions, active turn state, recent activity, branch/fork actions, rename/delete/hide actions, goal banners, and connection status.
- Conversation timeline with markdown, tool cards, command output display preferences, image generation cards, selectable messages, edit/fork actions, streaming rendering, and dynamic widget rendering.
- Discovery and connection flows for the local runtime, manual app-server URLs, SSH bootstrapping, LAN or remote servers, and Slingshot connected computers.
- Settings for appearance, fonts, conversation display, local terminal, experimental features, AI providers, diagnostics bundles, account/API key/base URL, connected servers, updates, and BuildKit developer controls.
- KittyStore, a KittyLitter-branded SideStore/AltStore-compatible source surface that shows the latest Litter IPA, all published version-history IPAs, source subscription links, direct IPA install links, download/share actions, and a Feather-style signing workspace for imported IPAs.
- Picture-in-Picture streaming cards through `AVPictureInPictureController` with a sample-buffer SwiftUI renderer.
- CarPlay voice scene support and experimental Apple Watch projection/complication targets.

## Files And Terminal

The Files button opens the iSH workspace rooted at `/root`. It uses the same fakefs command bridge used by Codex tool calls and the terminal panel, so file actions operate on the same filesystem the bot sees.

The file workspace includes list/grid views, breadcrumbs, search, sorting, filters, hidden-file toggles, quick locations, favorites, recents, inspectors, archive/build-artifact detection, and bot-context path copying. It also exposes file operations for creating, renaming, moving, duplicating, deleting, making executable, sharing, compressing, extracting, importing from iOS Files, and editing text/code files.

The terminal lives in Settings under `Local Tools -> Terminal`. `Open Terminal Here` from the file browser sets the starting directory for that same terminal. It is a command panel backed by the iSH command bridge: prompt, cwd tracking, history, shortcut keys, copy output, clear, and command execution all share the local fakefs runtime. It is not a separate iOS host shell.

BuildKit shortcuts in the file workspace and BuildKit settings call the same fakefs commands, including Swift check, Swift build, IPA build, build status, fakefs doctor, and `LitterBuild.json` creation.

## Appearance And Streaming

Appearance settings include system/light/dark mode selection, app-wide conversation font scaling, live preview, and separate light/dark theme pickers loaded from app resources.

Conversation wallpapers are scoped per thread or per server. Supported sources include built-in generated presets, light/dark app themes, solid colors, images from Photos, videos from Photos, and video URLs. Custom image preview uses a fitted renderer instead of blindly zooming the image to fill the screen.

Built-in background presets in `WallpaperManager` are Aurora, Terminal Grid, Blueprint, Midnight Neon, Ocean Glass, Sakura, Carbon Mesh, Solar Flare, Paper, and Forest.

Typing effects are persisted with the wallpaper scope and are driven by `StreamingEffectKind` plus HairballUI `StreamingTextEffect` implementations. Current options include Fade Edge, Sparkle, Glow Cursor, Wave, Scale Pop, Rainbow, Fire Trail, Explosion, Nyan Cat, Matrix Decode, Phosphor CRT, Shockwave, Typewriter, Terminal Scan, Soft Blur, Neon Pulse, Ghost Trail, Pixel Decode, Ink Spread, Slide Up, Glitch, and Focus Beam.

## AI Providers

Supported routes are:

- ChatGPT Account: the signed-in local Codex/ChatGPT route.
- Computer Bridge: a selected Mac, Windows, or Linux Codex app-server bridge.
- OpenAI-compatible server profiles: custom `/v1` endpoints for services such as Ollama or LM Studio running on another machine.

Legacy on-device AI state is cleaned up on load. Old local provider records are skipped, old local routing preferences fall back to automatic, old local model files are purged from the app documents directory, and only hosted routes are shown in the picker.

## Thread Goals

The Rust bridge advertises `features.goals` and exposes UniFFI methods for getting, setting, clearing, and hydrating thread goals. iOS stores hydrated goals in app state and renders goal status, objective, and usage in the home dashboard and PiP views. Goal persistence depends on the connected Codex server state database for that thread.

## Swift BuildKit

BuildKit is the experimental on-device Swift/iOS build path. Litter vendors Nyxian source, verifies it with `tools/scripts/verify-nyxian-source-import.sh`, and layers a Litter-specific native bridge on top. The public repo has source and reproducible scripts. Full Swift/iOS compilation still needs a private `LitterBuildKitAssets.zip` because Apple SDK files and compiled private frameworks are not committed.

The private asset pack must include:

- `Toolchains/Nyxian/CoreCompiler.framework`
- `Toolchains/Nyxian/CoreCompilerSupportLibs`
- `Toolchains/Nyxian/SwiftResourceDir`
- `Toolchains/Nyxian/LitterBuildKitNative.framework`
- `SDK/iPhoneOS<version>.sdk`
- optional `Toolchains/Nyxian/bin/litter-buildkit-runner`
- `manifest.json` with required paths and SHA256 entries

Important packaging rule: changing `ThirdParty/Nyxian/LitterBuildKitNative/**` does not change installed app behavior by itself. The app loads `LitterBuildKitNative.framework` from `LitterBuildKitAssets.zip`. After native bridge changes, rebuild and upload the private asset pack, update `LITTER_BUILDKIT_ASSET_URL` and `LITTER_BUILDKIT_ASSET_SHA256`, then build the IPA against that new asset.

Nyxian run/install mode needs more than compiler files. The installed app also needs the Apple ID and signing state used by the original Nyxian flow: an Apple ID login saved in Keychain, a SideStore-compatible Anisette server, the matching `.p12` signing identity, and the embedded provisioning profile from the signed Litter install.

BuildKit settings validates imported signing material before it is treated as usable. A bad `.p12` password, missing private key, untrusted certificate, or revoked certificate keeps Nyxian run/install blocked and shows the failure in status instead of silently accepting broken credentials. KittyStore also validates imported provisioning profiles for parse errors, expiration, missing developer certificates, bundle ID mismatch, and profile/certificate mismatch before certificate signing starts.

The Anisette picker can load SideStore's public server list from `https://servers.sidestore.io/servers.json`, falls back to known SideStore-compatible servers, and allows a custom server URL. Anisette only supplies Apple authentication metadata. It does not install apps by itself.

Full on-device install/refresh also needs SideStore-style local transport. Litter checks for a LocalDevVPN-style tunnel and reports that separately from signing readiness. Swift compilation and unsigned IPA packaging can still work without LocalDevVPN, but direct install/refresh stays blocked until that transport is available.

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

Compatibility shims are installed for common bot expectations:

```text
swift swiftc clang clang++ cc c++ ld ld64 xcodebuild xcrun plutil code
ar llvm-ar ranlib llvm-ranlib nm llvm-nm objdump llvm-objdump strip strings lipo
```

`litter-*` commands are the supported API. The compatibility shims cover the iOS-only cases Litter can run. BuildKit v1 is not desktop Xcode: SwiftPM package resolution, simulator workflows, Interface Builder, previews, App Store upload flows, Apple Developer portal management, and macOS toolchains are outside scope.

Useful in-app checks:

```bash
litter-fs-doctor
litter-build-status
litter-nyxian-status
litter-swift-selftest
printf 'print("Swift is running on device")\n' > /root/hello.swift
litter-swift-check /root/hello.swift
swiftc /root/hello.swift -o /root/hello
```

## Private BuildKit Asset Flow

`.github/workflows/buildkit-assets.yml` builds or reuses the private BuildKit asset pack on `macos-26`, verifies it, and can upload it to the private asset release repo. Defaults are:

- owner: `NightVibes33`
- repo: `litter-buildkit-assets`
- tag: `buildkit-ios26.4-v1`
- asset name pattern: `LitterBuildKitAssets-<run>-<attempt>.zip`

Use this flow when BuildKit source or private framework behavior changes:

1. Run `Build Private BuildKit Assets` on the branch containing the source fix.
2. Use `force_rebuild=true` when the native framework or Swift/LLVM payload must be rebuilt.
3. Set `use_existing_private_release=false` when you need to prove the old private release asset is not being reused.
4. Let the workflow upload a verified `LitterBuildKitAssets.zip` and update the unsigned IPA asset secrets.
5. Run or let it dispatch `.github/workflows/ios-unsigned-ipa.yml` on the same branch.
6. Install the new IPA and run `litter-swift-selftest` inside Litter.

Normal public IPAs keep the private compiler payload external for launch safety. The app can still download/install user-owned BuildKit assets from BuildKit settings.

## Unsigned IPA And AltStore Source

`.github/workflows/ios-unsigned-ipa.yml` builds a SideStore/AltStore-style unsigned IPA on `macos-26` with Xcode 26.3. It produces `build/unsigned-ipa/Litter-${VERSION}.ipa`, a SHA256 file, build metadata, release notes, `litter-update.json`, and `litter-altstore-source.json`.

Manual build modes are:

- `fast-device`: normal fast device lane. Reuses generated Rust assets when possible, strips stale signatures, removes embedded extensions, and keeps private BuildKit compiler payload external.
- `release-device`: full device lane. Rebuilds Rust instead of using the fast-device shortcut.
- `nyxian-private`: private/manual lane. Embeds verified private BuildKit assets and keeps `PlugIns/LiveProcess.appex`, the NSExtension required by original Nyxian/emexDE. This is not the default public IPA lane.

Every successful IPA build creates or updates a versioned GitHub release named `litter-v${VERSION}` and uploads the IPA, checksum, metadata, update JSON, source JSON, and release notes. The stable `app-source` release is also updated with `litter-altstore-source.json`, `litter-update.json`, and the source icon.

The AltStore/SideStore source is version-history first. Every successful versioned IPA release should remain installable through the app entry `versions` array with its own download URL, SHA-256 checksum, version date, size, minimum iOS version, and build version. Historical IPA downloads are also emitted as source `news` cards with direct IPA URLs. `tools/scripts/verify-altstore-source.py` runs before publish and fails the workflow if a version entry is only history text, lacks a direct IPA URL, lacks a checksum, duplicates another version/build, or is missing its matching news download card. Do not replace the source with only the latest build.

The in-app KittyStore tab reads that same source, rebrands the Litter feed for this app, and opens `sidestore://` or `altstore://` install/source URLs. Its Sign screen follows Feather's signer layout: IPA customization, certificate/provisioning selection, SideStore-style Apple ID/pairing/LocalDevVPN readiness, advanced Modify rows, Entitlements, Tweaks, Properties, and Start Signing. BuildKit settings can also import SideStore `.sideconf` account exports, preserving the Apple ID, password, signing certificate, certificate password, `local_user`, and `adiPB` fields while still validating the certificate before saving it. KittyStore stages those inputs into the native BuildKit driver and uses the vendored Feather/Zsign signing engine when the private BuildKit assets are rebuilt with `LITTER_BUILDKIT_ENABLE_KITTYSTORE_SIGNER=1`. The native signer supports default, force, and ad-hoc signing modes, dylib injection, dylib load-command removal, app-relative file removal, framework/plugin copying, entitlement edits, Feather-style Info.plist properties such as app appearance, minimum iOS version, file sharing, ProMotion, Game Mode, iPad fullscreen, URL-scheme removal, and tweak payload collection from dylibs, folders, zip files, and `.deb` packages that contain `data.tar` or `data.tar.gz`. The iOS IPA workflow also builds the vendored SideStore `minimuxer` Rust bridge through `tools/scripts/build-sidestore-minimuxer.sh`, links it into Litter with `KITTYSTORE_MINIMUXER_LINKED`, and keeps LocalDevVPN as the required tunnel app for SideStore-style on-device install/refresh/remove/list operations. Litter does not claim ownership of SideStore, Feather, or their supporting tools; SideStore, AltStore, Feather, LocalDevVPN, minimuxer, em_proxy, Jitterbug, and Zsign are credited in `THIRD_PARTY_NOTICES.md`.

Bots get a matching fakefs command surface so they do not have to scrape UI state: `litter-kittystore-status`, `litter-kittystore-source`, `litter-kittystore-versions`, `litter-kittystore-import-sideconf`, `litter-kittystore-validate-profile`, `litter-kittystore-plan`, `litter-kittystore-sign`, `litter-kittystore-install`, `litter-kittystore-refresh`, `litter-kittystore-remove`, and `litter-kittystore-installed`. Source, version, status, SideStore account import, profile validation, and plan commands return JSON or write JSON to `/root`; `litter-kittystore-sign` routes through native BuildKit and publishes the signed IPA back into fakefs when the private assets include the Feather/Zsign signer. Install/refresh/remove/installed-app browsing run the linked SideStore minimuxer bridge with a signed IPA or bundle ID, imported pairing file, optional provisioning profile, Apple ID settings, and LocalDevVPN connected; builds that do not include the bridge return `sidestore-minimuxer-not-linked` instead of pretending install is available.

All IPAs from this workflow are unsigned. They must be signed by SideStore, AltStore, Feather, or another signing tool before installation.

## Local Runtime Notes

- Local commands run inside iSH Alpine Linux, not the iOS host filesystem.
- The fakefs can see `/root`, `/tmp`, `/usr/local/bin`, `/root/.codex`, `/root/litter`, and app-provided mounts such as `/mnt/apps`.
- The fakefs cannot directly see arbitrary iOS sandbox paths such as `/private/var/mobile/...`; Litter stages native BuildKit files through app storage when native code must read them.
- `litter-dev-bootstrap` repairs expected fakefs utilities where possible. Some tools may still require Alpine packages.
- Shell failures with exit `-6` mean the iSH runtime was not bootstrapped. Start debugging at runtime/session initialization before looking at PATH, Swift, or BuildKit.
- PTY or streaming command errors usually mean the command RPC path and client process id handling need attention, not that the fakefs files disappeared.

## Make Targets

| Target | Description |
|---|---|
| `make ios-device-fast` | Fast iOS device build using the raw device staticlib lane. |
| `make ios-sim-fast` | Fast simulator build. |
| `make ios` | Full iOS package lane. |
| `make rust-check` | Host `cargo check` for shared Rust crates. |
| `make rust-test` | Host `cargo test` for shared Rust crates. |
| `make bindings` | Regenerate UniFFI Swift bindings. |
| `make xcgen` | Regenerate `Litter.xcodeproj` from `apps/ios/project.yml`. |
| `make alpine-fs` | Prepare the bundled Alpine fakefs. |
| `make nyxian-source-verify` | Verify the committed Nyxian source import. |
| `make nyxian-buildkit-assets` | Build/package private BuildKit assets on macOS. |
| `make nyxian-buildkit-assets-verify` | Validate a BuildKit asset ZIP or folder. |
| `make clean` | Remove build artifacts. |

## Credits And License

Litter is a fork of [dnakov/litter](https://github.com/dnakov/litter). This fork is maintained by NightVibes33 / ZYN / Zyn, which are the same maintainer identity for this fork, and includes additional iOS sideloading, update-source, local runtime, BuildKit, and UI work.

The sideloading and on-device install/refresh work also credits the wider ecosystem it builds around: SideStore, AltStore, LocalDevVPN, minimuxer, em_proxy, Jitterbug, and their maintainers/contributors. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the current attribution list.

Litter is not MIT licensed. The project uses GPLv3 with an additional GPLv3 section 7 permission for Apple App Store and iOS distribution. Vendored Nyxian/emexDE source is AGPL-3.0-or-later, OpenAI Codex source is Apache-2.0, and third-party components keep their own licenses. See [LICENSE](LICENSE), [AUTHORS.md](AUTHORS.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Contributing

The app, Rust bridge, fakefs runtime, and private BuildKit pipeline are tightly coupled. Keep PRs focused, include the workflow or command you used to verify the change, and update this README when behavior changes. BuildKit, Apple ID, signing, Anisette, LocalDevVPN, and AltStore source changes must document what changed and whether a new private BuildKit asset pack or IPA release is required. See [CONTRIBUTING.md](CONTRIBUTING.md) for contributor expectations.
