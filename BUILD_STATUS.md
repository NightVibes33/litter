# Build Status

Last verified public build:

- Commit: `ae9c4ad`
- Workflow: `Build Unsigned iOS IPA`
- Run: https://github.com/NightVibes33/litter/actions/runs/25643963735
- Result: green after restoring Files workspace navigation and local-model skill prompt routing
- Artifact mode: unsigned SideStore/AltStore IPA for re-signing

Current BuildKit state:

- Public repo contains the app-side BuildKit bridge, focused Nyxian/LLVM BuildKit source import, LiveContainer/ZSign source with a trimmed iOS arm64 OpenSSL.xcframework slice, fakefs command shims, fakefs doctor, native ABI wrapper source, private asset manifest contract, private GitHub Release downloader, and authenticated CI asset injection.
- Full on-device Swift/IPA building requires a private `LitterBuildKitAssets` bundle with CoreCompiler, Swift support libraries, `LitterBuildKitNative.framework`, and a user-owned `iPhoneOS26.4.sdk`. Runner mode additionally requires a packaged Nyxian runner; in-process mode now handles Swift jobs and minimal unsigned IPA packaging inside `LitterBuildKitNative.framework`.
- Apple SDK assets must not be committed to this public repository.

Latest implementation note:

- BuildKit now stages fakefs project files into app-visible `Documents/BuildKit/Jobs` before invoking native code.
- Settings -> BuildKit can store a private GitHub token in Keychain, download `LitterBuildKitAssets.zip` from a private release, verify SHA256, extract the ZIP, and install assets atomically.
- Private CI can authenticate private asset downloads with `LITTER_BUILDKIT_ASSET_TOKEN`; native driver loadability still requires the private framework to be embedded/codesigned in the sideload IPA.

Latest local changes awaiting CI verification:

- Added `litter-nyxian-status` readiness diagnostics and local-model tool exposure.
- Added focused Nyxian vendor/build/verify scripts and make targets for private asset packs.
- Added in-process unsigned IPA packaging and fakefs artifact export for BuildKit jobs.
- Updated README/development/audit docs with exact readiness gates, focused vendor state, and known limits.
- Focused Nyxian source import is recorded in `ThirdParty/Nyxian/VENDOR_LOCK.json`; full upstream refresh should run on macOS/CI, not iSH fakefs.

- Latest source-import hardening: `tools/scripts/verify-nyxian-source-import.sh` now verifies Builder.swift, LiveContainer/ZSign, the iOS arm64 OpenSSL slice, VENDOR_LOCK, and the bundled in-app Nyxian manifest.

Current runner asset workflow:

- `.github/workflows/buildkit-assets.yml` can build the private BuildKit asset ZIP on GitHub-hosted `macos-26`, verify it, optionally upload a 1-day debug artifact, and upload the release ZIP/SHA to the private asset repo when `LITTER_BUILDKIT_ASSET_TOKEN` is configured.
- Litter now reads the installed BuildKit manifest SDK path at runtime instead of assuming `SDK/iPhoneOS26.4.sdk`, so runner-produced SDK folders are accepted when the manifest verifies.
- BuildKit native wrapper packaging now stages flattened `MobileDevelopmentKit` public headers before compiling the in-process bridge, matching Xcode framework import layout for `<MobileDevelopmentKit/*.h>`.
