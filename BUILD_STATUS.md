# Build Status

Last verified public build:

- Commit: `113d0f3`
- Workflow: `Build Unsigned iOS IPA`
- Run: https://github.com/NightVibes33/litter/actions/runs/25633944189
- Result: green after the private BuildKit asset downloader and ZIP installer work
- Artifact mode: unsigned SideStore/AltStore IPA for re-signing

Current BuildKit state:

- Public repo contains the app-side BuildKit bridge, fakefs command shims, fakefs doctor, native ABI wrapper source, private asset manifest contract, private GitHub Release downloader, and authenticated CI asset injection.
- Full on-device Swift/IPA building requires a private `LitterBuildKitAssets` bundle with CoreCompiler, Swift support libraries, `LitterBuildKitNative.framework`, and a user-owned `iPhoneOS26.4.sdk`. Runner mode additionally requires a packaged Nyxian runner; in-process mode now handles Swift jobs and minimal unsigned IPA packaging inside `LitterBuildKitNative.framework`.
- Apple SDK assets must not be committed to this public repository.

Latest implementation note:

- BuildKit now stages fakefs project files into app-visible `Documents/BuildKit/Jobs` before invoking native code.
- Settings -> BuildKit can store a private GitHub token in Keychain, download `LitterBuildKitAssets.zip` from a private release, verify SHA256, extract the ZIP, and install assets atomically.
- Private CI can authenticate private asset downloads with `LITTER_BUILDKIT_ASSET_TOKEN`; native driver loadability still requires the private framework to be embedded/codesigned in the sideload IPA.

Latest local changes awaiting CI verification:

- Added `litter-nyxian-status` readiness diagnostics and local-model tool exposure.
- Added Nyxian vendor/build/verify scripts and make targets for private asset packs.
- Added in-process unsigned IPA packaging and fakefs artifact export for BuildKit jobs.
- Updated README/development/audit docs with exact readiness gates and known limits.
