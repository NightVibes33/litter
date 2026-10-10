# Repository Risk Register

Open engineering risks and their required order of resolution. The living
ownership map is [ARCHITECTURE.md](ARCHITECTURE.md); this file records only what
is still outstanding.

Findings were established by an audit on 2026-08-11 using compiler, test,
Clippy, shellcheck, link, and RustSec results. A search hit or line count alone
was not treated as proof of dead code. Counts below are dated to that audit and
should be re-measured, not trusted, before acting on them.

Re-measured 2026-09-22 by source inspection: the two Android dead-subtree items,
the Android build-config loop, the `RuntimeFlavorConfigTest` claim, and the
`kittylitter` version are resolved and corrected in place below. The P0 advisory
counts and the strict-Clippy finding count were **not** re-measured — both need a
full `cargo` build and `RustSec` run, so treat them as unverified until rerun.

## Alleycat dependency boundary

### Codex 0.160.1 mobile runtime upgrade (2026-10-07)

The root-owned sync script selects upstream release commit
`d27764b82f7118f674371e6d6e76271d9d606edb` and applies the refreshed mobile
overlays; the recorded submodule gitlink remains the bootstrap checkout.
Sequential application, a second idempotent sync, and dirty-checkout
preservation were checked against isolated source checkouts. The release's
bundled catalog includes GPT-6.1 Sol; authenticated account discovery still
determines availability in the app.

The mobile adapters now use source turn IDs for edit/fork boundaries and
hydrate retained history after `thread/revert`. They handle upstream image
references, network-policy startup arguments, realtime reasoning-status
defaults, and Pro Max account-plan mapping. The mobile host suite passed
868 tests with 7 ignored, the 14 Slingshot tests passed, and the locked
all-targets compilation check passed. Swift and Kotlin UniFFI bindings were
regenerated successfully. The iOS code-mode provider was adapted to the new
per-execution delegate API while retaining disabled JIT. Its separate Linux
execution test could not run because upstream does not publish the required
sandboxed V8 150.4.0 Linux archive (HTTP 404); native iOS validation is pending.
Native iOS archive, signing, device execution, and model discovery remain
required acceptance checks. This validation does not re-measure the RustSec
or strict-Clippy findings below. V8's source/ABI pin and the Alleycat Git
revision are unchanged.

Alleycat is not a Litter submodule. Litter consumes selected bridge crates by
Git revision, and that revision is the production dependency surface.

The 2.1.2 candidate pins `0xSero/alleycat@dcda34d1`, preserving the shipping
headless-launch lineage rather than substituting the divergent Alleycat `main`.
It refreshes native model/settings adapters, gives OMP an independent runtime,
and preserves Local Studio's explicit data directory across daemon upgrades.
Background launches avoid interactive login shells; bundled Local Studio Pi
uses plain Node rather than registering Electron as a foreground Dock app.

The installed `85c3d1e` candidate passed all 12 runtime routes on the first
attempt, returning 1,402 native catalog entries, 2,442 settings descriptors,
and 101 Codex configuration fields. Local Studio exposed 61 settings and 19
models through its signed bundled Pi metadata. Devin/Grok adapter tests passed
(117), as did both live published-schema tests and the full host library suite
(103). A preceding three-minute process sample found no foreground worker
registrations (88 valid samples, two inspection timeouts).

The `a5aaa9f6` follow-up stops reading Claude transcripts once session
summary metadata is found and removes runtime initialization from offline
status checks. Six focused regressions passed, including an unread 64 MiB
invalid transcript tail. The installed follow-up restarted successfully in
16 seconds with all 12 runtimes available, and a status read took 20 ms. Its
three-minute process sample found no foreground worker registrations (81 valid
samples, nine inspection timeouts). All catalogs passed, but Hermes settings
and model requests intermittently timed out in separate attempts under host
contention; the prior revision passed both together. This limitation and final
mobile/store acceptance remain open. The `dcda34d1` follow-up matches Hermes'
native GUI catalog options, avoiding probes of every saved custom endpoint
while preserving current/custom model IDs and native background refresh. Its
focused compatibility regression passed; final installed-host readback is pending.

Local Studio prefers the AppSupport CLI before `~/.local/bin`, so installed
upgrades must refresh both locations to avoid invoking an old pairing binary.
The updated CLI preserves an equal or newer running daemon and retains the
configured Local Studio data directory during upgrades.

An Alleycat change is not in Litter until the revision, lockfile, generated
bindings, and both mobile runtimes are verified.

## Local iOS code-mode validation

The integration branch supplies the upstream jitless in-process code-mode
runtime and builds matching sandboxed V8 device/simulator artifacts from pinned
source. Native compilation, signing/archive checks, and device execution remain
acceptance gates; this is not a claim that an installed build has passed them.
Android and Catalyst do not acquire the V8 production dependency. See
[LOCAL_CODE_MODE.md](LOCAL_CODE_MODE.md) for the source pin and verification path.

## P0 — dependency security

The 2026-10-10 security candidate upgrades the vulnerable Git, DNS, TLS,
archive, AWS JSON, JWT, SSH, and telemetry dependency families, including the
standalone vendor lockfiles. The registry inventory is reproducible with
`tools/scripts/audit-rust-dependencies.py`; local compatibility adapters require
source review in addition to registry checks.

The next candidate registry inventory reports zero advisories across nine tracked
Cargo lockfiles. Maintenance implementations are replaced by maintained
backends, and SSH RSA now uses AWS-LC; optional idevice classic certificates use
OpenSSL. The report explicitly inventories local/Git packages requiring source
review. These source replacements need compatibility and cryptographic review,
not merely a registry scan. See
[`DEPENDENCY_SECURITY_REMEDIATION.md`](DEPENDENCY_SECURITY_REMEDIATION.md) for
changes, RSA minimum-key/SHA-1 compatibility limits, and validation.

Swift Crypto, NIO, HTTP/2, SSL, and Vapor pins are upgraded; Feather uses a
reviewable local Zip boundary-validation patch. All tracked Swift pins have
zero OSV commit matches (`tools/scripts/audit-swift-dependencies.py`). All four
locked npm graphs audit clean, including the documentation and both Cloudflare
services. Unpatched Braces uses a bounded local source implementation; its
clean audit result requires source review as well.

**Do not suppress advisories.** GitHub's private inventory remains inaccessible.
GitHub last reported 32 default-branch alerts after PR #15, down from 36;
the independent candidate's zero findings are not a GitHub alert count.
Recheck GitHub after merge. CI plus installed-device network, SSH, pairing,
and signing acceptance remain release gates.

## P1 — incomplete user-visible behavior

- Android Ghostty loads after the GLAD/EGL/GLES linking repair, but its OpenGL
  4.3 renderer cannot create a surface on the tested Android 17 emulator's
  OpenGL ES 3.1 context. The basic terminal command field supports line input
  and output; native rendering, ANSI screen semantics, selection, and full-screen
  terminal applications still require a proper OpenGL ES port and device QA.
- Android's realtime speaker control updates a boolean but does not switch the
  physical audio route. `RealtimeWebRtcSession` forces speakerphone on at session
  start and restores the previous route at teardown; the toggle never reaches
  `AudioManager`.
- Realtime input/output meters do not use actual audio-level telemetry on either
  platform.
- Voice handoff cannot select an arbitrary existing thread through one typed
  end-to-end contract.
- Android lacks the plugin/file `@` autocomplete behavior recorded in its QA
  matrix.
- Windows SSH/direct fallback remains incomplete; detached SSH bridge launch is
  explicitly unimplemented for PowerShell remotes.
- Realtime response cancellation is observable in the bundled Codex runtime but
  is not exposed by its app-server protocol, so Watch offers only the supported
  stop control. A true barge-in action awaits that upstream request.
- ACP cannot truthfully implement direct `command/exec`, terminate, stdin, or
  resize without a session-bearing Codex request. Fork currently creates a new
  ACP session projection; it does not clone complete server-side history.
- Several Pi/Claude bridge status/config/skills/MCP responses are intentionally
  synthesized or empty and require live conformance coverage before expansion.
- Android's `Route.Sessions` screen subtree and the `HomeAppTakeoverRow` /
  `savedAppsByThread` / `sessionApps` feeder pipeline were removed. Re-measured
  2026-09-22: no `Route.Sessions`, `SessionsScreen`, `SessionsUiState`,
  `SessionsDerivation`, or `HomeAppTakeoverRow` symbol exists anywhere under
  `apps/android`; the `apps/android/docs/qa-matrix.md` text that still described
  them was corrected too, so no stale reference remains.

Each voice item is device-gated. A green unit test is not proof that speaker
routing, metering, Bluetooth, interruption, or handoff works on hardware.

## P1 — concentration and state risk

The highest-maintenance files remain the Rust reducer, `MobileClient`, the
handwritten FFI client, the parser, iOS `ConversationView`, and Android's
conversation timeline. Together they centralize unrelated responsibilities and
make review difficult. Split them only at typed ownership seams with replay
fixtures; a line-count-only extraction would increase risk.

The strict Clippy run leaves 30 structural findings in `codex-mobile-client`:
UniFFI constructor/default shape, large public result or command variants,
high-arity boundary methods, two complex internal types, and test-module
placement. These should remain visible until the boundary design is changed;
blanket allows would erase useful architecture signals.

## P2 — repository and release maintenance

- The shared Cargo manifest tracks `ish-embed-host` from a moving `main` branch
  while the lockfile pins one commit. Replace it with an explicit revision or
  release after local-runtime acceptance.
- `mobile-release.yml` is a large, duplicated release-control surface. Manual,
  automatic, distribution, TestFlight, and Play paths are distinct acceptance
  surfaces, but shared setup and artifact verification should be factored into
  reusable workflows.
- `services/kittylitter` targets v0.3.10 alongside mobile 2.1.2. The release guard
  rejects changing that package after its tag and rejects mismatched mobile
  pairing URLs; future host changes require a coordinated version bump.
- Android's custom `buildConfigField`s, `manifestPlaceholders`, and their
  `<meta-data>` tags were removed from `apps/android/app/build.gradle.kts`.
  Re-measured 2026-09-22: no `buildConfigField`, no
  `RUNTIME_STARTUP_MODE` / `APP_RUNTIME_TRANSPORT` / `ENABLE_ON_DEVICE_BRIDGE`
  reference survives anywhere under `apps/android`, and `RuntimeFlavorConfigTest`
  no longer exists.
- Historical Git objects still contain a 78.2 MB
  `apps/android/app/src/main/jniLibs/arm64-v8a/libcodex.so`, plus 11.0 MB and
  10.0 MB `home_cat_entrance.png` / `home_cat.png` predecessors, in a 146 MB
  pack. Removing them requires a coordinated history rewrite and is
  intentionally outside routine cleanup.
- The iOS and Android `home_cat.webp` / `home_cat_entrance.webp` pairs are
  byte-identical across platforms (~4.5 MB of tracked duplication). No other
  tracked asset justifies a conversion-only cleanup wave.
- Markdown lint reports hundreds of existing line-length/table-layout issues,
  mainly in `AGENTS.md` and the Android QA matrix. Relative local links pass. Fix
  formatting when those documents are otherwise edited; do not generate a
  review-obscuring reflow-only commit.
- Android lint reports zero errors, 105 warnings, and 14 hints. Most are KTX
  modernization suggestions and coordinated dependency upgrades. The deliberate
  synchronous encrypted-preference commits, adaptive icon API qualifier, ChromeOS
  ABI gap, and complex Droid vector remain visible. Do not confuse this clean
  error gate with physical Android acceptance.

## Retained despite having no callers

Lack of an internal caller is not proof of removability. These are retained
deliberately:

  dead code. Superseded SSH and realtime boundary wrappers require live mobile
  acceptance before any later removal.
- `tools/scripts/codex-e2e-proof.sh`, `tools/scripts/local-studio-e2e-proof.sh`,
  and their shared `tools/scripts/assert-local-studio-proof.py` are operator
  acceptance harnesses driven by a locally built `kittylitter` binary. Nothing in
  the Makefile, CI, or docs invokes them; they are run by hand.

## Recommended execution waves

1. **Security compatibility.** Iroh/Hickory and Russh/SHA-2 are upgraded. Next,
   upgrade upstream Codex/RMCP and track plist/quick-xml plus RSA owners. Gate
   each change with RustSec, host tests, both mobile builds, and physical
   network/SSH/MCP checks.
2. **Alleycat lineage.** Reconcile the production pin's 56-commit lineage onto
   Alleycat `main`, run live bridge conformance, then update Litter's explicit
   revision.
3. **Voice hardware.** Implement real route selection and level telemetry in
   native WebRTC adapters, add the typed existing-thread handoff contract in
   Rust, and validate interruption/Bluetooth/speaker behavior on iOS and Android
   devices.
4. **Android reachability.** Done: the `Route.Sessions` subtree, the saved-app
   home takeover, and the runtime-flavor build config loop are removed. Keep the
   remaining `apps/android/docs/qa-matrix.md` text honest when it changes.
5. **Conversation decomposition.** Profiling is done: `testStreamingRenderCachePerformance_1000Tokens`
   streams a growing paragraph in 1000 appends and now measures 25 ms, down from 3.56 s
   before the append fast path, and the interaction latency markers are in place
   (`make measure-latency`). Next, capture replay fixtures, then extract render-only
   sections, hydration boundaries, and reducer domains without creating native shadow
   state.
6. **Release reuse.** Extract shared workflow setup and artifact assertions,
   keeping store ownership, signing, installed runtime, and live endpoint gates
   distinct.
7. **Asset/history maintenance.** Schedule any Git history rewrite as a separate
   coordinated migration.

## Acceptance gates

Shared-behavior changes are not accepted on source review alone. The minimum
stack is:

1. full `codex-mobile-client` host test suite;
2. `codex-slingshot` tests and shellcheck templates;
3. UniFFI binding regeneration;
4. iOS simulator or device build;
5. Android unit tests, debug APK assembly, and lint with zero errors; and
6. physical-device verification for audio, networking, local runtimes, and
   release-only behavior.

Live external-agent conformance remains opt-in. Physical-device voice, network,
local-runtime, and store-release acceptance remain separate gates.
