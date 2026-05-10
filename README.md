# litter

<p align="center">
  <img src="apps/ios/Sources/Litter/Resources/brand_logo.png" alt="litter logo" width="180" />
</p>

<p align="center">
  Native iOS client for <a href="https://github.com/openai/codex">Codex</a>. Connect to local or remote servers, manage sessions, browse and edit iSH files, and run agentic coding workflows from iPhone and iPad.
</p>

<p align="center">
  <a href="https://kittylitter.app"><img src="docs/badges/website.svg" alt="kittylitter.app" /></a>
  &nbsp;
  <a href="https://apps.apple.com/us/app/kittylitter/id6759521788"><img src="docs/badges/app-store.svg" alt="App Store" /></a>
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
make ios-device-fast   # fast iOS device build
make ios-sim-fast      # fast iOS simulator build
```

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for prerequisites, full build options, TestFlight/App Store release, and SSH setup.

## Repository Layout

```
apps/ios/                  iOS app (Litter scheme, project.yml is source of truth)
shared/rust-bridge/
  codex-mobile-client/     Shared Rust client crate + UniFFI surface for iOS
  codex-ios-audio/         iOS-only audio/AEC crate
shared/third_party/codex/  Upstream Codex submodule
patches/codex/             Local patch set applied during builds
tools/scripts/             Cross-platform helper scripts
```

## Architecture

Litter uses a Rust core (`codex-mobile-client`) through UniFFI-generated Swift bindings. Swift owns the iOS UI, permissions, notifications, document import surfaces, and platform APIs. Session state, streaming, hydration, discovery, and auth logic live in Rust. Chat image attachments are downsampled before upload so large iPhone photos do not become oversized base64 payloads.

## iOS File Workspace

The Files button on the home toolbar opens a real local iSH file workspace rooted at `/root`. It lists actual fakefs folders and files through `ishRun`, supports hidden files, folder navigation, creating files/folders, renaming, deleting, importing documents from iOS Files, and opening/saving text/code files in a built-in editor. iOS Files imports stream into the fakefs instead of loading the full source file into memory, and imported names are collision-safe so an existing fakefs file is not silently overwritten. This is intentionally local-first; remote file management should use SSH/Codex tools until a dedicated remote file API is wired.

## AI Providers and Local Models

Litter supports a provider foundation for hosted OpenAI, OpenAI-compatible LAN endpoints such as Ollama or LM Studio, and on-device GGUF model imports/downloads. PC-hosted endpoints should use an OpenAI-compatible `/v1` base URL such as `http://192.168.1.20:11434/v1`. On-device model downloads support recommended GGUF catalog entries, Hugging Face GGUF search, and direct GGUF URLs, then check the current device profile including RAM, storage, thermal state, Low Power Mode, and Metal availability before install. Re-importing or re-downloading a model with the same filename creates a numbered copy instead of replacing the existing GGUF record.

The chat runtime picker is explicit: users choose **ChatGPT Account**, **Computer Bridge**, or **On-device Model** before choosing the model. ChatGPT uses the signed-in local Codex/ChatGPT route, Computer Bridge uses the selected Mac/Windows/Linux Codex bridge server, and On-device Model selects installed `local-gguf:<id>` models that route turns through the native llama.cpp runtime. The home chip and conversation header show the active route as labels such as `ChatGPT • GPT-5.3`, `Bridge • Codex`, or `On-device • Gemma`.

The AI settings screen now exposes real model controls instead of hiding them in code: default provider routing, post-download validation, cellular download policy, idle unload behavior, thermal warnings, and per-model runtime settings for context window, max output tokens, temperature, top-p, top-k, repeat penalty, thread count, Metal/CPU fallback, streaming, tool mode, tool rounds, KV cache mode, and prompt override. The device panel shows the current thermal state (`Nominal`, `Fair`, `Serious`, or `Critical`) alongside RAM, free storage, Metal device, GPU families, and safe context guidance. Serious or critical thermal pressure automatically downgrades local recommendations and clamps runtime settings.

On-device models now have a native llama.cpp token-generation bridge wired into the Swift runtime when `apps/ios/Frameworks/llama.xcframework` is present, plus guarded fakefs tools, approval request state for shell/write actions, retry events, streaming tool-call state, device-derived context defaults, and accurate streamed download progress with cancel support, automatic post-install smoke validation, manual Verify Model actions, and native cancellation hooks. Installed verified models can open a Local Agent workspace with context file selection, streaming generation, approval-gated shell/write tools, diff previews, retries, cancellation, partial-output recovery, and the selected model's runtime settings. Local GGUF models are also surfaced in the normal model picker as `local-gguf:<id>` selections, and selected local models route normal conversation turns through `LocalLlamaRuntime` instead of the hosted Codex server. Main-chat local turns insert real user/assistant/tool timeline items, reuse the same shell/write approval sheet, support cancellation from the normal Stop button, recover from malformed tool JSON with a retry prompt, and store a per-model Codex-readiness score after validation. The local tool loop now includes read/list/search, text grep, repo-map context, shell with approval, full-file writes, and safer `replace_text` edits with diff preview before apply. Context management builds a compact repo map plus truncated file packs from the thread cwd and absolute fakefs file mentions. The score is not a quality guarantee: small models can execute the same app-side loop, but answer quality still depends on the GGUF family, size, quantization, context, and tool-following behavior.

TurboQuant is modeled as an experimental llama.cpp runtime capability, not a fake always-on switch. The unsigned iOS build now compiles the `animehacker/llama-turboquant` fork by default through `apps/ios/scripts/build-llama-xcframework.sh`, records the resolved fork commit in `apps/ios/Frameworks/llama.version`, and uses a dedicated TurboQuant cache/stamp so older upstream llama.cpp frameworks are not reused accidentally. The native bridge passes advanced llama.cpp runtime settings through to the engine, including Metal GPU layer selection, CPU fallback, thread count, top-p, top-k, repeat penalty, and KV cache type (`F16`, `Q8`, `Q4`, or TurboQuant modes when the linked ggml runtime reports them). If the fork exposes TurboQuant GGML types at runtime, the settings UI enables TurboQuant 3-bit/4-bit KV cache choices; if not, TurboQuant remains unavailable instead of silently faking support.

## iOS Local Runtime Notes

On iOS, local terminal commands run inside an embedded iSH Alpine Linux fakefs. The default local home is `/root`, app-created files can be bridged through `/mnt/apps`, and Codex settings live at `/root/.codex`. Litter bridges `/root/.codex` to the app's native Codex home, so custom skills installed from the local terminal under `$CODEX_HOME/skills` are stored where the app runtime can read them. Restart or reload Codex after adding a new skill if it does not appear immediately.

## Unsigned iOS IPA

The workflow at `.github/workflows/ios-unsigned-ipa.yml` builds a real-device unsigned IPA artifact named `Litter-iOS26-Unsigned-SideStore-AltStore.ipa`. It uses the repo's iOS 26 build lane on GitHub-hosted `macos-26` with Xcode `26.3`, packages `Payload/Litter.app`, and removes signing leftovers. New pushes still trigger CI, but in-progress runs are not cancelled. The Rust cache now stores both `apps/ios/GeneratedRust` and the generated Swift UniFFI binding so restored static libraries are accepted, and llama.cpp has its own XCFramework cache. The artifact is intended for SideStore/AltStore-style re-signing; it will not install directly on a stock iPhone while unsigned.

## Contributing

Litter is under active development and a lot of features are in flight. PRs are welcome but will likely only be merged if they're small and target a specific problem — sweeping refactors and new features tend to collide with work already underway. See [CONTRIBUTING.md](CONTRIBUTING.md) before opening one.

## License

Litter is licensed under the GNU General Public License version 3 with an additional permission under GPLv3 section 7 for Apple App Store and iOS distribution. See [LICENSE](LICENSE).

## Make Targets

| Target | Description |
|---|---|
| `make ios-device-fast` | Fast device build (raw staticlib) |
| `make ios-sim-fast` | Fast simulator build |
| `make ios` | Full package lane (device + sim + xcframework) |
| `make rust-check` | Host `cargo check` for shared Rust crates |
| `make rust-test` | Host `cargo test` for shared Rust crates |
| `make bindings` | Regenerate UniFFI Swift bindings |
| `make xcgen` | Regenerate Xcode project from `project.yml` |
| `make clean` | Remove all build artifacts |
