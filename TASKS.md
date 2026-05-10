# Tasks

## Done

- Add focused Nyxian source import for BuildKit research.
- Add fakefs BuildKit command shims.
- Add BuildKit settings surface.
- Add private asset manifest template.
- Add private asset packaging and CI preparation scripts.
- Add build script and source for the private `LitterBuildKitNative.framework` ABI wrapper.
- Add Settings -> BuildKit import flow for expanded private asset folders.
- Add private GitHub Release download/install flow for BuildKit asset ZIPs with Keychain token storage.
- Add Nyxian vendor/build/verify helper scripts and make targets for private BuildKit asset packs.
- Add in-process Nyxian IPA packaging and fakefs artifact export for generated unsigned IPAs.
- Add `litter-nyxian-status` readiness reporting for users and bots.
- Add fakefs core device repair for `/dev/random` and `/dev/urandom`.
- Add local-model tools for BuildKit status, fakefs doctor, Swift checks, build/test, IPA build/package, and build cancellation.
- Add real iOS Files file/folder imports into fakefs, image preview support, archive detection/extract actions, and chat attachment path mentions.
- Add clickable Hugging Face model detail sheets, downloadable GGUF sibling cards, empty default search, and persistent download/install progress states.

## Remaining External Blockers

- Build or obtain `CoreCompiler.framework` and `CoreCompilerSupportLibs` from Nyxian/LLVM-On-iOS.
- Build or obtain a separate Nyxian BuildKit runner only if using runner mode; in-process mode no longer requires it.
- Package a user-owned `iPhoneOS26.4.sdk` from Xcode into a private `LitterBuildKitAssets` bundle.
- Provide a signing identity/provisioning profile for real install/launch validation on device.

## Next Engineering Work

- Run `make nyxian-vendor` on macOS to refresh the focused upstream Nyxian/LLVM-On-iOS BuildKit source import when network access is available.
- Run `make nyxian-buildkit-assets` on macOS with Xcode/private asset paths to create the private `LitterBuildKitAssets.zip`.
- Upload the private ZIP with `tools/scripts/upload-buildkit-assets-release.sh`, then set `LITTER_BUILDKIT_ASSET_URL`, `LITTER_BUILDKIT_ASSET_SHA256`, and `LITTER_BUILDKIT_ASSET_TOKEN` GitHub secrets for private BuildKit-enabled sideload builds.
- Validate Settings -> BuildKit private release download on device with a private token.
- Validate `litter-swift-check` and `litter-ipa-build` on a paired iPhone after installing the private asset bundle.
- Add a native preview or quick-look path for unsupported image formats and large files.
- Consider bundling or bootstrapping archive extractors (`unzip`, `unar`/`unrar`, `bsdtar`) so archive extraction works on fresh fakefs installs.
- Run full `make nyxian-vendor` only from macOS/CI; iSH fakefs should use the committed focused import plus private downloadable BuildKit assets.

## Current BuildKit Finish Work

- Added fakefs-to-host staging for Swift source/project manifests before native compilation.
- Added optional in-process Nyxian driver source path in `LitterBuildKitInProcess.mm`.
- Added minimal in-process unsigned IPA packaging and artifact export back into `/root/builds/<job-id>`.
- Added fakefs distro commands `litter-env-report`, `litter-dev-bootstrap`, and `litter-nyxian-status`.
- Remaining private validation: compile `LITTER_BUILDKIT_NATIVE_MODE=inprocess` with real CoreCompiler/support libs/SDK and run on a sideloaded device.
