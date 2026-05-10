# Tasks

## Done

- Add Nyxian source import for BuildKit research.
- Add fakefs BuildKit command shims.
- Add BuildKit settings surface.
- Add private asset manifest template.
- Add private asset packaging and CI preparation scripts.
- Add build script and source for the private `LitterBuildKitNative.framework` ABI wrapper.
- Add Settings -> BuildKit import flow for expanded private asset folders.
- Add fakefs core device repair for `/dev/random` and `/dev/urandom`.
- Add local-model tools for BuildKit status, fakefs doctor, Swift checks, build/test, IPA build/package, and build cancellation.
- Add real iOS Files file/folder imports into fakefs, image preview support, archive detection/extract actions, and chat attachment path mentions.
- Add clickable Hugging Face model detail sheets, downloadable GGUF sibling cards, empty default search, and persistent download/install progress states.

## Remaining External Blockers

- Build or obtain `CoreCompiler.framework` and `CoreCompilerSupportLibs` from Nyxian/LLVM-On-iOS.
- Build or obtain a Nyxian BuildKit runner executable that links CoreCompiler and consumes `request.json`.
- Package a user-owned `iPhoneOS26.4.sdk` from Xcode into a private `LitterBuildKitAssets` bundle.
- Provide a signing identity/provisioning profile for real install/launch validation on device.

## Next Engineering Work

- Run `tools/scripts/build-litter-buildkit-native.sh` on macOS or provide a monolithic private driver.
- Run `tools/scripts/package-buildkit-assets.sh` on macOS with Xcode, private asset paths, and `NYXIAN_BUILDKIT_RUNNER` when using the default wrapper.
- Set `LITTER_BUILDKIT_ASSET_URL` and `LITTER_BUILDKIT_ASSET_SHA256` GitHub secrets for private BuildKit-enabled sideload builds.
- Validate `litter-swift-check` and `litter-ipa-build` on a paired iPhone after installing the private asset bundle.
- Add a native preview or quick-look path for unsupported image formats and large files.
- Consider bundling or bootstrapping archive extractors (`unzip`, `unar`/`unrar`, `bsdtar`) so archive extraction works on fresh fakefs installs.

## Current BuildKit Finish Work

- Added fakefs-to-host staging for Swift source/project manifests before native compilation.
- Added optional in-process Nyxian driver source path in `LitterBuildKitInProcess.mm`.
- Added fakefs distro commands `litter-env-report` and `litter-dev-bootstrap`.
- Remaining private validation: compile `LITTER_BUILDKIT_NATIVE_MODE=inprocess` with real CoreCompiler/support libs/SDK and run on a sideloaded device.
