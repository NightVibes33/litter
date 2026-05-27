# Repository Guidelines

## Project Structure & Module Organization
- `apps/ios/Sources/Litter/` contains the iOS app code.
- `apps/ios/Sources/Litter/Views/` holds SwiftUI screens, `Models/` contains app state/session logic, and `Bridge/` contains JSON-RPC + C FFI bridge code.
- `shared/rust-bridge/codex-mobile-client/` is the Rust client library consumed by Swift through UniFFI. It owns the public UniFFI surface, generated upstream RPC coverage, canonical store/reducer state, hydration, discovery, SSH, and runtime logic.
- `shared/rust-bridge/codex-bridge/` is legacy C-FFI support that should not be used for new runtime features.
- `apps/ios/Sources/Litter/Bridge/Rust*.swift` maps Swift to the shared Rust layer.
- `shared/third_party/codex/` is the upstream Codex submodule.
- `apps/ios/GeneratedRust/` contains local generated Rust artifacts for iOS builds. These artifacts are not committed.
- `apps/ios/Frameworks/` contains downloaded/package-lane iOS XCFrameworks. These artifacts are not committed.
- `apps/ios/project.yml` is the source of truth for project generation; regenerate `apps/ios/Litter.xcodeproj` instead of hand-editing project files.

## Architecture
- **iOS root layout:** `ContentView` uses a `ZStack` with a persistent `HeaderView`, main content area, and a `SidebarOverlay` that slides from the left.
- **iOS state management:** `AppStore` (Rust, via UniFFI) is the canonical runtime state owner. `AppModel` is the thin Swift observation shell over Rust snapshots and updates. `AppState` is UI-only state.
- **iOS server flow:** discovery and SSH are separate utility bridges; thread/session/account operations come from generated Rust RPC plus store updates.
- **Message rendering:** Litter supports reasoning/system sections, code block rendering, inline images, and generative UI widgets.

### Shared Rust Layer
- `codex-mobile-client` is the single public Rust mobile crate. Keep one generated Swift binding surface; do not split UniFFI across multiple runtime crates.
- Realtime voice uses libwebrtc on iOS. The Rust layer owns signaling, session lifecycle, transcript state, and handoff orchestration.
- `AppStore` owns snapshots, typed updates, and the small set of truly composite/store-local actions.
- `AppClient` is the public UniFFI client surface for direct server operations and typed results.
- `DiscoveryBridge` and `SshBridge` are separate Rust utility surfaces. Do not move discovery/SSH policy back into Swift.
- iOS uses UniFFI-generated Swift plus thin bridge helpers.
- iOS Debug/device links the raw static library in `apps/ios/GeneratedRust/ios-device/libcodex_mobile_client.a`. Package/release lanes may create `apps/ios/Frameworks/codex_mobile_client.xcframework`, but that is not the default debug/device artifact.

## Feature Placement Rules
- Prefer Rust first for session state, thread state, streaming, hydration, approvals, auth/account, discovery merge policy, voice transcript/handoff normalization, and status normalization.
- Keep Swift thin. Platform code should own UI, platform persistence, platform permissions, audio/session APIs, notifications, ActivityKit/CarPlay services, and render-only projections.
- Do not parse upstream wire-format strings in Swift. If a status, event kind, or payload shape matters, expose it as a typed UniFFI enum/record from Rust.
- Do not duplicate merge/reducer/state-machine logic in Swift. Shared reconciliation belongs in Rust reducer/store code.
- If shared Rust needs a direct server operation, expose it on `AppClient` with a mobile-owned request/result shape instead of adding a handwritten wrapper on `AppStore`.
- Keep the public UniFFI surface handwritten and narrow. Put reconciliation policy in handwritten Rust reducer/reconcile code.
- `AppStore` should stay minimal: snapshots, subscriptions, and truly composite/store-local actions only. Direct server operations belong on `AppClient`.
- Prefer authoritative updates from upstream events, then targeted refresh/reconcile when upstream events are insufficient.
- New boundary types crossing into Swift should be UniFFI-safe Rust records/enums.
- Generated Rust sources must stay local-only. Use `*.generated.rs` filenames and do not commit generated Rust files; regenerate them via `./shared/rust-bridge/generate-bindings.sh`.

## Build System
The root `Makefile` is the primary build interface. It orchestrates submodule sync, patching, UniFFI binding generation, Rust cross-compilation, raw staticlib generation, optional xcframework packaging, Xcode project generation, and iOS builds.

### Common targets
| Target | Description |
|---|---|
| `make ios` | Full iOS package lane: sync -> patch -> bindings -> rust -> xcframework -> litter-ish -> xcgen -> simulator build |
| `make ios-sim` | Full iOS package lane + simulator build |
| `make ios-sim-fast` | Fast iOS simulator lane using raw simulator staticlib outputs in `GeneratedRust/ios-sim` |
| `make ios-device` | Full iOS package lane + device build |
| `make ios-device-fast` | Fast iOS device lane using raw staticlib outputs in `GeneratedRust/` |
| `make rust-ios-package` | Build/package Rust for iOS |
| `make rust-ios-sim-fast` | Build raw Rust simulator staticlib + headers only |
| `make rust-ios-device-fast` | Build raw Rust device staticlib + headers only |
| `make rust-check` | Host `cargo check` for shared Rust crates |
| `make rust-test` | Host `cargo test` for shared Rust crates |
| `make bindings` | Regenerate UniFFI Swift bindings |
| `make xcgen` | Regenerate `Litter.xcodeproj` from `project.yml` |
| `make test` | Run Rust + iOS tests |
| `make testflight` | Full iOS build + TestFlight upload |
| `make clean` | Remove build artifacts + stamp cache |

### Configuration overrides
- `IOS_SIM_DEVICE` — simulator name.
- `XCODE_CONFIG` — Xcode build configuration.
- `IOS_SCHEME` — Xcode scheme.
- `IOS_DEPLOYMENT_TARGET` — minimum iOS version.

### Individual scripts
- `./apps/ios/scripts/build-rust.sh` — cross-compile Rust for iOS.
- `./apps/ios/scripts/build-ghostty.sh` — build pinned Ghostty iOS renderer artifacts.
- `./apps/ios/scripts/download-litter-ish.sh` — fetch the pinned `dnakov/litter-ish` release.
- `./apps/ios/scripts/sync-codex.sh` — sync Codex submodule + apply patches.
- `./apps/ios/scripts/sync-ghostty.sh` — apply Litter's iOS Ghostty embedding patch.
- `./apps/ios/scripts/regenerate-project.sh` — regenerate Xcode project via xcodegen.
- `./apps/ios/scripts/testflight-upload.sh` — archive, export IPA, upload to TestFlight.
- `./shared/rust-bridge/generate-bindings.sh` — generate UniFFI Swift bindings.
- `./tools/scripts/testflight-feedback.sh` — fetch TestFlight feedback.
- `./tools/scripts/fetch-mobile-store-artifacts.py` — fetch TestFlight feedback/crash artifacts.
- `./tools/scripts/triage-mobile-feedback.py` — rerunnable GitHub + TestFlight triage ledger.

## Autonomous Debugging Runbook
- Prefer the fast lanes for local iteration before package/release lanes: `make ios-sim-fast` and `make ios-device-fast`.
- For repeated feedback/crash triage across GitHub and TestFlight, start with `./tools/scripts/triage-mobile-feedback.py --last-hours 24`.
- For iOS simulator debugging, install the latest built app directly from DerivedData before launching it.
- For Xcode project regeneration, use `make xcgen` or `./apps/ios/scripts/regenerate-project.sh`.
- Mobile logs stay local: use Xcode/device console for iOS and normal Rust `tracing` output.

## Coding Style & Naming Conventions
- Swift style follows standard Xcode defaults: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for properties/functions.
- Dark theme: pure `Color.black` backgrounds, `#00FF9C` accent, `SFMono-Regular` font throughout.
- Keep concurrency boundaries explicit (`actor`, `@MainActor`) and avoid cross-actor mutable state.
- Group iOS files by layer (`Views`, `Models`, `Bridge`).

## Testing Guidelines
- iOS tests: prefer XCTest under `apps/ios/Tests/LitterTests/` with files named `*Tests.swift`.
- iOS test command: `xcodebuild test` using the same project/scheme/destination pattern as build commands.
- Rust tests: use `make rust-test` when cargo is available.

## Commit & Pull Request Guidelines
- Use concise, imperative commit subjects with optional scope.
- PRs should include purpose, key changes, verification steps, and screenshots for UI changes.
- If project structure changes, include updates to `apps/ios/project.yml` and mention whether project regeneration was run.
