# Nyxian BuildKit Audit

## Current Import

Litter vendors a focused BuildKit-facing Nyxian source subset under `ThirdParty/Nyxian`: CoreCompiler source, MobileDevelopmentKit compiler/linker source, selected LindChain project/core helpers, LiveProcess entrypoint code, and Litter's `LitterBuildKitNative` bridge. `ThirdParty/LLVM-On-iOS` tracks the public LLVM/Swift toolchain build entrypoint. The public repo does not commit Apple SDK payloads or private binary toolchain packs.

## Runtime Path

1. iSH fakefs commands such as `litter-swift-build` write request files under `/root/.litter-buildkit/requests`.
2. `LitterBuildKit` monitors requests, stages text Swift sources/resources from fakefs into `Documents/BuildKit/Jobs/<job-id>`, and calls `LitterBuildKitNative.framework` through `litter_buildkit_run_json`.
3. In-process mode links Nyxian MobileDevelopmentKit/CoreCompiler glue into the native framework and can run Swift typecheck/build jobs without spawning a separate runner.
4. IPA commands write a minimal iOS app `Info.plist`, copy staged resources, create a stored ZIP with `Payload/<App>.app`, and return artifact metadata.
5. Litter copies returned host artifacts back to fakefs under `/root/builds/<job-id>/` so bots can inspect/export the output.

## Build Asset Path

Run these on macOS with full Xcode:

```bash
make nyxian-vendor
make nyxian-buildkit-assets
make nyxian-buildkit-assets-verify
LITTER_BUILDKIT_ASSET_TOKEN=<token> tools/scripts/upload-buildkit-assets-release.sh
```

The generated private asset bundle must contain:

- `Toolchains/Nyxian/CoreCompiler.framework`
- `Toolchains/Nyxian/LitterBuildKitNative.framework`
- `Toolchains/Nyxian/CoreCompilerSupportLibs`
- `SDK/iPhoneOS26.4.sdk/SDKSettings.plist`
- optional runner at `Toolchains/Nyxian/bin/litter-buildkit-runner` when using runner mode

## Readiness Checks

Use `litter-nyxian-status --timeout 60` from fakefs. A real ready state requires all of these to pass:

- private manifest installed
- CoreCompiler framework available
- native driver framework installed and loadable
- CoreCompiler support libraries installed
- iPhoneOS SDK installed
- declared runner installed when the manifest is runner mode
- manifest capabilities include Swift build and unsigned IPA build/package

## Known Limits

This bridge is now real infrastructure, not a mock UI, but it is not a replacement for every Xcode feature. Full SwiftPM resolution, asset catalog compilation, storyboard compilation, code signing, app extensions, Swift macro/plugin execution, lldb, simulator/device launch, and rich compiler diagnostics still need separate implementation. The current in-process packager intentionally creates unsigned IPAs for sideload signing workflows; it does not produce App Store/TestFlight-signed builds.
