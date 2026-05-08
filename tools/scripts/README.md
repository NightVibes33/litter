# Shared Scripts (Planned)

Cross-platform automation scripts will move here over time.

- `build-android-rust.sh`: builds Android Rust bridge JNI libs into `apps/android/core/bridge/src/main/jniLibs`.
- `codex-app-driver.applescript`: launches `Codex.app`, opens a project root, creates a thread, and pastes/sends prompts through GUI scripting for desktop-side conversation automation.
- `codex-desktop-controller.mjs`: launches or attaches to a remote-debugging-enabled `Codex.app` instance, then drives the real renderer UI through CDP so it can open projects, create threads, send prompts, wait for the turn to finish, and dump the visible transcript as JSON without macOS accessibility scripting.
- `deploy-android-ondevice.sh`: builds Rust JNI libs, assembles `onDeviceDebug`, installs on a target device (`--serial`/`ANDROID_SERIAL`), and launches the app.
- `download-llama-xcframework.sh`: downloads and verifies the pinned llama.cpp iOS XCFramework into `apps/ios/Frameworks`.
- `ensure-ish-dev-random.sh`: repairs missing `/dev/null`, `/dev/random`, and `/dev/urandom` devices inside the iSH fakefs.
- `switch-app-identity.sh`: switches local app IDs between `com.sigkitten.litter` and `com.<your-identifier>.litter` for Android+iOS (`--to your-identifier --identifier <name>`), with optional `--team-id` for iOS signing. For iOS it updates `apps/ios/project.yml` and regenerates `apps/ios/Litter.xcodeproj` via `xcodegen` (no direct `.xcodeproj` edits).

Common `codex-desktop-controller.mjs` flows:

```bash
# Launch a separate Codex instance with Electron remote debugging enabled.
node tools/scripts/codex-desktop-controller.mjs launch \
  --app "/Applications/Codex copy.app" \
  --port 9333 \
  --user-data-dir /tmp/codex-desktop-controller-profile

# Reuse that same instance on later commands. Add --fresh-launch only if you
# intentionally want a brand new app instance on the same port/profile setup.
node tools/scripts/codex-desktop-controller.mjs thread-state --port 9333 --launch

# Attach to an already-running automation instance and inspect the active thread.
node tools/scripts/codex-desktop-controller.mjs thread-state --port 9333

# Send one turn into the current thread, wait for the assistant to finish, and print JSON.
node tools/scripts/codex-desktop-controller.mjs run-turn \
  --port 9333 \
  --message 'Reply with exactly: OK'

# Start a fresh thread in a sidebar project, run the first turn, and print the final transcript.
node tools/scripts/codex-desktop-controller.mjs run-turn \
  --port 9333 \
  --project codex-test \
  --message 'Reply with exactly: OK'
```
