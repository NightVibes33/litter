# Build Status

Last verified public build:

- Commit: `f6bd4b5de88bd933e8728c4a9a0913cd67d1c02f`
- Workflow: `Build Unsigned iOS IPA`
- Run: https://github.com/NightVibes33/litter/actions/runs/25632730287
- Result: green before the private BuildKit asset downloader work
- Artifact mode: unsigned SideStore/AltStore IPA for re-signing

Current BuildKit state:

- Public repo contains the app-side BuildKit bridge, fakefs command shims, fakefs doctor, native ABI wrapper source, private asset manifest contract, private GitHub Release downloader, and authenticated CI asset injection.
- Full on-device Swift/IPA building requires a private `LitterBuildKitAssets` bundle with CoreCompiler, Swift support libraries, `LitterBuildKitNative.framework`, a Nyxian runner or monolithic driver, and a user-owned `iPhoneOS26.4.sdk`.
- Apple SDK assets must not be committed to this public repository.

Latest implementation note:

- BuildKit now stages fakefs project files into app-visible `Documents/BuildKit/Jobs` before invoking native code.
- Settings -> BuildKit can store a private GitHub token in Keychain, download `LitterBuildKitAssets.zip` from a private release, verify SHA256, extract the ZIP, and install assets atomically.
- Private CI can authenticate private asset downloads with `LITTER_BUILDKIT_ASSET_TOKEN`; native driver loadability still requires the private framework to be embedded/codesigned in the sideload IPA.
