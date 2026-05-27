# Build Status

Last verified public build:

- Commit: `d45ea1c4`
- Workflow: `Build Unsigned iOS IPA`
- Run: https://github.com/NightVibes33/litter/actions/runs/26510892012
- Result: green after retrying unsigned IPA release publishing
- Artifact mode: unsigned KittyStore/AltStore-compatible IPA for re-signing

Current BuildKit state:

- Public repo contains the app-side BuildKit bridge, focused Nyxian/LLVM BuildKit source import, LiveContainer/ZSign source with a trimmed iOS arm64 OpenSSL.xcframework slice, fakefs command shims, fakefs doctor, native ABI wrapper source, private asset manifest contract, private GitHub Release downloader, and authenticated CI asset injection.
- Full on-device Swift/IPA building requires a private `LitterBuildKitAssets` bundle with CoreCompiler, Swift support libraries, Swift resource files, `LitterBuildKitNative.framework`, and a user-owned `iPhoneOS26.4.sdk`. Runner mode additionally requires a packaged Nyxian runner; in-process mode now handles Swift jobs and minimal unsigned IPA packaging inside `LitterBuildKitNative.framework`.
- Apple SDK assets must not be committed to this public repository.

Latest implementation note:

- BuildKit now stages fakefs project files into app-visible `Documents/BuildKit/Jobs` before invoking native code.
- Settings -> BuildKit can store a private GitHub token in Keychain, download `LitterBuildKitAssets.zip` from a private release, verify SHA256, extract the ZIP, and install assets atomically.
- Private CI can authenticate private asset downloads with `LITTER_BUILDKIT_ASSET_TOKEN`; native driver loadability still requires the private framework to be embedded/codesigned in the sideload IPA.

Latest changes after the last verified build:

- `0e2854a7` fixes the embedded KittyStore archive blocker by moving store metadata mutation behind `StoreApp.applyEmbeddedKittyStoreMetadata()`.
- `0e2854a7` also removes delayed embedded-store rebranding passes, renames the host/embedded glue to KittyStore, rebrands widget fallback assets/status codes, and keeps legacy SideStore URL schemes only as compatibility aliases.
- `0e2854a7` makes `apps/ios/scripts/regenerate-project.sh` POSIX `sh` compatible and marks intentional XcodeGen script phases with `basedOnDependencyAnalysis: false`.
- CI run https://github.com/NightVibes33/litter/actions/runs/26528958664 was in progress when this note was updated.

Current runner asset workflow:

- `.github/workflows/buildkit-assets.yml` can build the private BuildKit asset ZIP on GitHub-hosted `macos-26`, verify it, optionally upload a 1-day debug artifact, and upload the release ZIP/SHA to the private asset repo when `LITTER_BUILDKIT_ASSET_TOKEN` is configured.
- Litter now reads the installed BuildKit manifest SDK path at runtime instead of assuming `SDK/iPhoneOS26.4.sdk`, so runner-produced SDK folders are accepted when the manifest verifies.
- BuildKit native wrapper packaging now stages flattened `MobileDevelopmentKit` public headers before compiling the in-process bridge, matching Xcode framework import layout for `<MobileDevelopmentKit/*.h>`.
- BuildKit asset CI now checks for a verified private release before rebuilding Swift/LLVM, restores both finished and partial compiler caches, and saves partial outputs after failed long builds so retries do not restart from zero.
- BuildKit source rebuilds are now opt-in with `force_rebuild=true`; normal runs skip successfully if no reusable private release/cache exists instead of spending hours compiling Swift/LLVM by default.
- The native wrapper now also stages flattened `CoreCompiler` headers, fixing the final packaging failure from run `25644535373` after CoreCompiler itself succeeded.
- Unsigned IPA CI no longer builds or restores llama.cpp; on-device GGUF inference is disabled and local/private models should use a PC-hosted OpenAI-compatible endpoint.
