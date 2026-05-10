# Tasks

## Done

- Add Nyxian source import for BuildKit research.
- Add fakefs BuildKit command shims.
- Add BuildKit settings surface.
- Add private asset manifest template.
- Add private asset packaging and CI preparation scripts.
- Add fakefs core device repair for `/dev/random` and `/dev/urandom`.
- Add local-model tools for BuildKit status, fakefs doctor, Swift checks, build/test, IPA build/package, and build cancellation.

## Remaining External Blockers

- Build or obtain `CoreCompiler.framework` and `CoreCompilerSupportLibs` from Nyxian/LLVM-On-iOS.
- Build private `LitterBuildKitNative.framework` implementing `litter_buildkit_run_json`.
- Package a user-owned `iPhoneOS26.4.sdk` from Xcode into a private `LitterBuildKitAssets` bundle.
- Provide a signing identity/provisioning profile for real install/launch validation on device.

## Next Engineering Work

- Implement the private native-driver framework against CoreCompiler.
- Run `tools/scripts/package-buildkit-assets.sh` on macOS with Xcode and private asset paths.
- Set `LITTER_BUILDKIT_ASSET_URL` and `LITTER_BUILDKIT_ASSET_SHA256` GitHub secrets for private BuildKit-enabled sideload builds.
- Validate `litter-swift-check` and `litter-ipa-build` on a paired iPhone after installing the private asset bundle.
