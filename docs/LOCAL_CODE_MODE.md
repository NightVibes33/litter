# Local iOS code mode

Alley Cat supplies Codex's upstream `InProcessCodeModeSession` to the embedded
app server. A managed patch exposes an optional provider while retaining the
original `start(args)` API. The mobile provider initializes V8 with JIT disabled
before creating a session, and delegates nested calls to Codex's existing tool
and approval machinery. Requests for heap limits fail explicitly because the
upstream in-process runtime does not enforce those limits.

The device and simulator libraries use rusty_v8 150.4.0, matching the pinned
Codex dependency. `.github/workflows/ios-code-mode-runtime.yml` builds the native
libraries with `v8_enable_sandbox` from immutable upstream revision
`5c15a6995c9bb4bacd3e341b59fff32c909c80bf`. The ordinary published iOS binaries
lack the sandbox configuration used by Codex and cannot substitute for these
artifacts. Archive and generated bindings are produced together and checked
with SHA-256 before consuming them. Their environment overrides apply only to
iOS Rust compilation; host binding generation, Android, and Catalyst retain
their existing dependency paths.

For a local iOS build, download both `ios-code-mode-runtime-*` artifacts into
`build/ios-code-mode`, preserving the target subdirectories, or recursively
check out rusty_v8 at the pinned revision into `build/rusty-v8-source` and run:

```sh
tools/scripts/build-ios-code-mode-runtime.sh aarch64-apple-ios
tools/scripts/build-ios-code-mode-runtime.sh aarch64-apple-ios-sim
```

The host regression is opt-in (`--features local-code-mode-tests`) so ordinary
host/Android tests do not acquire a native V8 requirement. Use the matching
OpenAI Codex `rusty-v8-v150.4.0` sandbox archive and generated bindings via
`RUSTY_V8_ARCHIVE` and `RUSTY_V8_SRC_BINDING_PATH`. It executes a real cell with JIT disabled and checks that
unsupported resource limits are rejected. Native archive/link validation runs
in the iOS workflows. Device acceptance still requires opening a local thread
with a server-advertised code-mode model, executing a cell and nested tool,
checking cancellation, and verifying PiP while backgrounded.

The model picker uses the live, paginated server catalog. It accepts newly
advertised models without a baked-in allowlist. The pinned bundled catalog
includes GPT-6-Astra, GPT-5.6-Sol, GPT-5.6-Terra, and GPT-5.6-Luna;
GPT-6.1-Sol, GPT-6-Sol, and GPT-6-Luna require the connected server to advertise
those IDs. Adding a display name locally does not grant backend model access.
