# Nyxian in Alley Cat — cached builds, free Apple Accounts, and ROMs

## Reuse the cache without breaking in-app ChatGPT

Run **Build Unsigned iOS IPA** with `build_mode=cached-full-sideload`. It preserves the embedded Nyxian/emexDE module, `CoreCompiler.framework`, `MobileDevelopmentKit.framework`, `LiveProcess.appex`, KittyStore, and the native `NyxianCommandBridge` used by ChatGPT for projects/create/build/run/diagnostics. It restores the **pinned, provenance-verified** toolchain from Actions cache or the retained artifact. On a cache miss it fails early rather than recompiling LLVM/Swift. Use `full-sideload` when a new toolchain actually must be built.

The user-provided `Nyxian.ipa` 0.11.5 is a **standalone app**. Extracting its compiled frameworks and blindly injecting them into Alley Cat cannot replace the matching native build: module ABI, extension signing, framework load paths, and source/LLVM/Xcode pinning must match. Preserve the existing native bridge. Do not treat an embedded IPA as an in-process IDE.

For comparison, sample SHA-256 values:
- Nyxian 0.11.5 IPA: `71c2f523a0344d87cd5df9401f32e3e450f966185b819d0ae36a5e3e2ae9b469`
- `procursus-jailed.zip`: `4d694cde94d019144abe9e2870f84906138f472dc704a645766c9ee309f7795d`

These samples are **not** currently hosted as GitHub Actions artifacts. The hashes document which uploads were inspected; do not claim the runner fetched them.

## Free Apple Account path

The embedded Nyxian onboarding no longer automatically calls `checkSigningSetup()` or demands a P12/certificate picker. Export/build actions remain available. Users may sign and install the unsigned Alley Cat IPA and exported user projects with their own Apple Account in KittyStore/SideStore where supported; a paid Developer Program membership is not required for ordinary sideloading.

This does **not** bypass Apple provisioning restrictions. Personal Team signing normally has a seven-day profile, three active apps/device, and ten App IDs per seven days. It cannot create reserved entitlements, kernel privileges, or unsupported extensions; `LiveProcess.appex`, JIT, or ROM userspace may still need additional compatibility checks on an actual free-account-signed device.

## Procursus ROM

The provided ZIP contains ROM ID `org.emexlabs.procursus.jailed` and its manifest requires Nyxian **0.11.5 or newer**. Users should select it through Nyxian's compatible recovery/ROM import interface; CI must **not** preinstall it into the app or expand its executables into the host sandbox.

The standalone Nyxian app has a volume-down recovery interaction. **Do not assume** that opening the embedded Nyxian screen inside Alley Cat uses the same standalone `SceneDelegate` boot path. Volume-down handling, import, and subsequent virtual userspace behavior require physical-device verification in the embedded host before being marked implemented. A jailed ROM is not an unrestricted kernel jailbreak.

## Required checks

1. Cache-only runner either restores the verified complete toolchain or fails without a new compiler build.
2. The resulting Alley Cat archive contains emexDE/Compiler/LiveProcess and the unchanged in-app ChatGPT bridge.
3. On a free Apple Account, install/launch Alley Cat; exercise Nyxian create/build/export with no P12 prompt, then verify KittyStore signing separately.
4. On a physical device, independently verify the ROM recovery UI, volume button detection, ROM import, and any extension/runtime privileges.
