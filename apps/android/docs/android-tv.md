# Alley Cåt on Android and Android TV

One APK supports Android phones, tablets, and Android TV (Android 8.0/API 26 or newer). The package remains `com.sigkitten.litter.android`. The TV launcher uses a remote-first home screen with visible focus outlines, Add server, Settings, Apps, and recent conversations. Conversation, settings, and connection screens currently reuse upstream Android UI; full remote-only acceptance testing is still required before calling TV support complete.

## Build

Run the **Android APK Release** GitHub Actions workflow on the integration branch with `build_only=true`. Choose `arm64-v8a` for ARM64 devices, `x86_64` for Intel/AMD emulators, or both for a universal APK. Choose `armeabi-v7a` for a separate 32-bit APK. Download the `alleycat-android-*` artifact. Debug builds are signed with the runner's debug key, require no Play credentials, and are for development. A subsequent runner may generate a different debug key, requiring uninstall/reinstall; use a stable release key for persistent installations.

Local build with Java 21, Android SDK 36, NDK 30.0.14904198, Rust, cargo-ndk, Zig 0.15.2, and the repository's native prerequisites:

```sh
make android ANDROID_ABIS=arm64-v8a,x86_64
adb install -r apps/android/app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.sigkitten.litter.android/com.litter.android.MainActivity
```

ARMv7 (`armeabi-v7a`) is now available as a separate CI build selection for 32-bit Android systems, including Chromecast with Google TV. Native compilation and device acceptance for this new target are pending; a configured target is not yet a verified working APK. KittyStore signing and Nyxian iOS toolchains remain iOS-specific; Android uses upstream's Android runtime.

## Device acceptance

- Phone/tablet: mobile home remains available; connect, send a message, open a conversation, and return with Back.
- TV: app appears in the TV launcher and opens without touch/camera/microphone hardware.
- Remote: initial focus is on Add server; arrows move among actions and conversations; Select opens; Back returns.
- Verify text input with the TV keyboard and an external keyboard, scrolling, server setup, authentication, approvals, and reconnect.
- Check conversations and settings for unreachable touch-only controls; these screens need device validation and may need additional TV adaptations.
- Test both ARM64 hardware and an x86-64 TV emulator before release.

## TV account sign-in

ChatGPT login on a TV uses the pinned Codex provider's device authorization
endpoints. Scan the QR code or open `https://auth.openai.com/codex/device` on your phone, sign in,
and enter the one-time code displayed on the TV. The TV polls for approval
and stores the resulting tokens in its existing encrypted credential store;
it does not need a browser or localhost redirect. Codes expire after 15
minutes. Back/Close cancels polling. If required, enable device code
authorization in your ChatGPT security settings. Remote-control enrollment
still uses the separate browser step-up flow; device login does not grant
remote-control enrollment automatically.

The TV home uses the actual iOS default icon, shared theme colors, larger
workspace/conversation typography, rounded cards and visible remote focus.
Phone/tablet home remains unchanged. ARMv7 native compilation and physical-TV
sign-in, focus, scrolling and conversation acceptance remain required.

## QR login to first conversation repair

TV home provides New Chat even when there are no recent conversations. It uses
the existing shared thread-start flow, restores stored authentication, and
connects the on-device runtime if no server is connected. Missing authentication
opens the account sheet; successful TV account login resumes chat creation.
Starting/error states are visible instead of a misleading empty-session
connection prompt. Phone login behavior is unchanged.

Native APK validation and physical ARMv7 TV acceptance are pending. Remote
instrumentation checks cover initial New Chat focus, activation with no sessions,
and navigation to Settings. QR approval, runtime startup, model discovery, and
sending a message still require a physical device.

## Android parity repair validation

The expanded TV repair is under native validation, not accepted as full iOS parity.
It adds the 13 iOS icon choices, TV-sized settings/account sheets, home-only
Advanced Files/Terminal launchers, and local file CRUD/import/export/editor.
Chat archive errors remain visible and local rows are hidden only after RPC success.
Speaker selection now updates the active WebRTC audio route.
The editor rejects externally changed content before saving, preserves file modes,
and warns before discarding edits. Folder deletion does not follow symlinks;
workspace system roots remain protected. Operations are serialized and imports
retain the folder selected when the picker opened. Files waits for runtime bootstrap.

Acceptance still requires ARMv7 unit tests, APK assembly, lint, and physical TV
QR-to-chat, remote navigation, file operations, microphone/speaker/Bluetooth checks.
Instrumentation compilation alone does not prove those device checks.
iOS-only integrations such as Nyxian and Apple StoreKit have no equivalent
Android implementation in this patch. Full browser parity (archive tools, batch
selection, search, remote files) remains separate work.
