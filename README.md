# litter

<p align="center">
  <img src="apps/ios/Sources/Litter/Resources/brand_logo.png" alt="litter logo" width="180" />
</p>

<p align="center">
  Native iOS + Android client for <a href="https://github.com/openai/codex">Codex</a>. Connect to local or remote servers, manage sessions, and run agentic coding workflows from your phone.
</p>

<p align="center">
  <a href="https://kittylitter.app"><img src="docs/badges/website.svg" alt="kittylitter.app" /></a>
  &nbsp;
  <a href="https://apps.apple.com/us/app/kittylitter/id6759521788"><img src="docs/badges/app-store.svg" alt="App Store" /></a>
  &nbsp;
  <a href="https://kittylitter.app/android-beta"><img src="docs/badges/android-beta.svg" alt="Android Beta" /></a>
</p>

## Screenshots (iOS)

<p align="center">
  <img src="docs/screenshots/01-hero-iphone-1320x2868.png" alt="Home" width="200" />
  <img src="docs/screenshots/02-remote-iphone-1320x2868.png" alt="Remote servers" width="200" />
  <img src="docs/screenshots/07-generative-ui-iphone-1320x2868.png" alt="Generative UI" width="200" />
  <img src="docs/screenshots/05-realtime-voice-iphone-1320x2868.png" alt="Realtime voice" width="200" />
</p>

## Quick Start

```bash
make ios-device-fast   # fast device build
make ios-sim-fast      # fast simulator build
make android-emulator-fast  # fast Android emulator build
```

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for prerequisites, full build options, TestFlight/App Store release, and SSH setup.

## Repository Layout

```
apps/ios/                  iOS app (Litter scheme, project.yml is source of truth)
apps/android/              Android app (Compose UI, Gradle build)
shared/rust-bridge/
  codex-mobile-client/     Shared Rust client crate + UniFFI surface (iOS & Android)
  codex-ios-audio/         iOS-only audio/AEC crate
shared/third_party/codex/  Upstream Codex submodule
patches/codex/             Local patch set applied during builds
tools/scripts/             Cross-platform helper scripts
```

## Architecture

Both platforms share a single Rust core (`codex-mobile-client`) via UniFFI-generated bindings. Platform code (Swift/Kotlin) stays thin: UI, permissions, notifications, and platform APIs only. Session state, streaming, hydration, discovery, and auth logic live in Rust.

## AI Providers and Local Models

Litter supports a provider foundation for hosted OpenAI, OpenAI-compatible LAN endpoints such as Ollama or LM Studio, and on-device GGUF model imports. PC-hosted endpoints should use an OpenAI-compatible `/v1` base URL such as `http://192.168.1.20:11434/v1`. On-device model imports are checked against the current device profile, including RAM, storage, thermal state, Low Power Mode, and Metal availability, so the app can recommend safe model sizes before users try to load them.

## iOS Local Runtime Notes

On iOS, local terminal commands run inside an embedded iSH Alpine Linux fakefs. The default local home is `/root`, app-created files can be bridged through `/mnt/apps`, and Codex settings live at `/root/.codex`. Litter bridges `/root/.codex` to the app's native Codex home, so custom skills installed from the local terminal under `$CODEX_HOME/skills` are stored where the app runtime can read them. Restart or reload Codex after adding a new skill if it does not appear immediately.

## Unsigned iOS IPA

The workflow at `.github/workflows/ios-unsigned-ipa.yml` builds a real-device unsigned IPA artifact named `Litter-iOS26-Unsigned-SideStore-AltStore.ipa`. It uses the repo's iOS 26 build lane on GitHub-hosted `macos-26` with Xcode `26.3`, packages `Payload/Litter.app`, and removes signing leftovers. The artifact is intended for SideStore/AltStore-style re-signing; it will not install directly on a stock iPhone while unsigned.

## Contributing

Litter is under active development and a lot of features are in flight. PRs are welcome but will likely only be merged if they're small and target a specific problem â sweeping refactors and new features tend to collide with work already underway. See [CONTRIBUTING.md](CONTRIBUTING.md) before opening one.

## License

Litter is licensed under the GNU General Public License version 3 with an additional permission under GPLv3 section 7 for Apple App Store and Google Play distribution. See [LICENSE](LICENSE).

## Make Targets

| Target | Description |
|---|---|
| `make ios-device-fast` | Fast device build (raw staticlib) |
| `make ios-sim-fast` | Fast simulator build |
| `make ios` | Full package lane (device + sim + xcframework) |
| `make android-emulator-fast` | Fast Android emulator build |
| `make android` | Full Android pipeline |
| `make rust-check` | Host `cargo check` for shared Rust crates |
| `make rust-test` | Host `cargo test` for shared Rust crates |
| `make bindings` | Regenerate UniFFI Swift + Kotlin bindings |
| `make xcgen` | Regenerate Xcode project from `project.yml` |
| `make clean` | Remove all build artifacts |
