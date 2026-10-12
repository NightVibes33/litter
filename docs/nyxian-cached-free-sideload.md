# Nyxian in Alley Cat — cached builds, free Apple Accounts, and ROMs

## Reuse the cache without breaking in-app ChatGPT

Run **Build Unsigned iOS IPA** with `build_mode=cached-full-sideload`. It preserves the embedded Nyxian/emexDE module, `CoreCompiler.framework`, `MobileDevelopmentKit.framework`, `LiveProcess.appex`, KittyStore, and the native `NyxianCommandBridge` used by ChatGPT for projects/create/build/run/diagnostics. It restores the **pinned, provenance-verified** toolchain from Actions cache or the retained artifact. On a cache miss it fails early rather than recompiling LLVM/Swift. Use `full-sideload` when a new toolchain actually must be built.

The user-provided `Nyxian.ipa` 0.11.5 is a **standalone app**. Extracting its compiled frameworks and blindly injecting them into Alley Cat cannot replace the matching native build: module ABI, extension signing, framework load paths, and source/LLVM/Xcode pinning must match. Preserve the existing native bridge. Do not treat an embedded IPA as an in-process IDE.

For comparison, sample SHA-256 values:
- Nyxian 0.11.5 IPA: `71c2f523a0344d87cd5df9401f32e3e450f966185b819d0ae36a5e3e2ae9b469`
- `procursus-jailed.zip`: `4d694cde94d019144abe9e2870f84906138f472dc704a645766c9ee309f7795d`

These samples are **not** currently hosted as GitHub Actions artifacts. The hashes document which uploads were inspected; do not claim the runner fetched them.

## Free Apple Account path

The embedded Nyxian onboarding no longer automatically forces the signing popup. Export/build actions remain available. **Nyxian only:** open **Nyxian → Settings → Signing** to access the upstream `CertificateImporter`. A free Apple ID user may select their `SideStore.p12` file, enter its password and tap **Import**. This stores the signing identity in Nyxian's original `LCUtils` storage (`LCCertificateData` / `LCCertificatePassword`) for `ZSigner` without redirecting users to KittyStore or Feather. Paid Apple Developer Program membership is not a requirement for a valid seven-day Apple *development* certificate.

Nyxian reads the **installed host app's** `embedded.mobileprovision` for its native ZSigner checks. The imported P12 must correspond to a certificate authorized by that provisioning profile. `LiveProcess.appex` must also remain present with its development entitlements (`get-task-allow`); a mismatched P12/profile or stripped extension needs correcting at install/signing time. A Personal Team certificate is supported in principle, but standard seven-day expiry, app limits and restricted-entitlement limitations still apply. This change does **not** bypass iOS provisioning or grant additional privileges.

## Procursus ROM

The provided ZIP contains ROM ID `org.emexlabs.procursus.jailed` and its manifest requires Nyxian **0.11.5 or newer**. Users should select it through Nyxian's compatible recovery/ROM import interface; CI must **not** preinstall it into the app or expand its executables into the host sandbox.

The standalone Nyxian app has a volume-down recovery interaction. **Do not assume** that opening the embedded Nyxian screen inside Alley Cat uses the same standalone `SceneDelegate` boot path. Volume-down handling, import, and subsequent virtual userspace behavior require physical-device verification in the embedded host before being marked implemented. A jailed ROM is not an unrestricted kernel jailbreak.

## Required checks

1. Cache-only runner either restores the verified complete toolchain or fails without a new compiler build.
2. The resulting Alley Cat archive contains emexDE/Compiler/LiveProcess and the unchanged in-app ChatGPT bridge.
3. On a free Apple Account, install/launch Alley Cat; open **Nyxian → Settings → Signing**, select **SideStore.p12**, enter the password, and verify native Nyxian/ZSigner validation. Exercise create/build/export, then run/install on device only after the provisioning and extension preflight passes.
4. On a physical device, independently verify the ROM recovery UI, volume button detection, ROM import, and any extension/runtime privileges.
