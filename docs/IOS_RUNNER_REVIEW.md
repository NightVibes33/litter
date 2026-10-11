# iOS runner review — 2026-10-11

Reviewed main cea32f39 failures before this follow-up. Both unsigned and
TestFlight failed in netwatch 0.19.1; there was no IPA or upload from these runs.

## Repairs and checks

- Restored the shared Darwin routing constants used by netwatch on iOS, with
  values verified against Apple XNU route.h and compile-time libc comparisons
  on macOS. Kept the real routing queries and monitoring implementation.
- Production-lockfile netwatch check passed for aarch64-apple-ios.
- Standalone ABI graph passed for aarch64-apple-ios and x86_64-apple-darwin.
- Added build-rust.sh --check-device to both iOS lanes, using the same SDK,
  profile and pinned V8 assets as their actual builds. This checks the complete
  mobile Rust graph before static-library compilation and optimization.
- All 73 shell run steps in the five workflows below passed bash -n; all nine
  inline Python heredocs passed AST parsing. All 27 referenced local shell/Python
  scripts exist and passed their syntax checks. These are syntax checks, not
  executions of SDK commands, secret-dependent operations or external APIs.

## Reviewed downstream stages

Unsigned: Alpine filesystem; optional private assets; minimuxer generation;
matching compiler artifacts; Swift import/project patches; Xcode generation;
archive; dynamic framework validation; LiveProcess extension; native compiler
bridge; optional BuildKit payload checks; IPA packaging; artifact/release upload.

TestFlight: release prep packaging; signing assets; archive/export; upload;
distribution finalization and existing-build recovery. The prior Apple 422
beta-review rejection is a separate distribution condition; a Rust compile
check cannot establish that Apple will accept a submission.

The latest compiler/V8 jobs passed. The current failed runs never executed
the later archive/package/upload stages. Passing their syntax and reviewing
artifact handoffs cannot guarantee their future result; real SDK runners
remain the validation gate. Runtime Nyxian launch also needs device testing.

## Workflow inventory

### ios-unsigned-ipa.yml

- build-unsigned-ipa: Show toolchain
- build-unsigned-ipa: Verify Nyxian source import
- build-unsigned-ipa: Resolve emexDE Swift revision
- build-unsigned-ipa: Verify KittyStore/Feather integration
- build-unsigned-ipa: Install Rust native build dependencies
- build-unsigned-ipa: Ensure Swift UniFFI binding
- build-unsigned-ipa: Check prebuilt Rust device library
- build-unsigned-ipa: Install Rust rebuild dependencies
- build-unsigned-ipa: Warm Rust dependency cache
- build-unsigned-ipa: Check full iOS Rust graph before static library build
- build-unsigned-ipa: Build Rust iOS device library
- build-unsigned-ipa: Prepare Alpine filesystem
- build-unsigned-ipa: Compute private BuildKit source fingerprint
- build-unsigned-ipa: Prepare private BuildKit assets
- build-unsigned-ipa: Verify private BuildKit assets are prepared
- build-unsigned-ipa: Check KittyStore minimuxer bridge cache
- build-unsigned-ipa: Install KittyStore minimuxer rebuild dependencies
- build-unsigned-ipa: Build KittyStore minimuxer bridge
- build-unsigned-ipa: Install matching upstream compiler artifacts
- build-unsigned-ipa: Normalize emexDE generated Swift imports
- build-unsigned-ipa: Patch fast unsigned device project
- build-unsigned-ipa: Generate Xcode project
- build-unsigned-ipa: Reset SwiftPM binary artifact cache
- build-unsigned-ipa: Build unsigned archive
- build-unsigned-ipa: Verify embedded dynamic frameworks
- build-unsigned-ipa: Build Nyxian LiveProcess extension
- build-unsigned-ipa: Build ChatGPT native compiler bridge against archived Nyxian
- build-unsigned-ipa: Verify archived BuildKit asset payload
- build-unsigned-ipa: Verify private BuildKit payload is external
- build-unsigned-ipa: Package KittyStore/AltStore IPA artifact
- build-unsigned-ipa: Publish unsigned IPA release asset

### ios-testflight.yml

- testflight-preflight: Validate App Store Connect app record
- prepare-release-assets: Checkout submodules with retry
- prepare-release-assets: Install build dependencies
- prepare-release-assets: Validate TestFlight Rust generated cache
- prepare-release-assets: Prime sccache
- prepare-release-assets: Normalize emexDE generated Swift imports for TestFlight prep
- prepare-release-assets: Validate cached Alpine identity
- prepare-release-assets: Prepare iOS release assets
- prepare-release-assets: Check KittyStore minimuxer bridge cache
- prepare-release-assets: Install KittyStore minimuxer rebuild dependencies
- prepare-release-assets: Build KittyStore minimuxer bridge
- prepare-release-assets: Check emexDE CoreCompiler artifact cache
- prepare-release-assets: Prepare emexDE CoreCompiler artifacts
- prepare-release-assets: Patch emexDE CoreCompiler Swift frontend for TestFlight CI
- prepare-release-assets: Package iOS release prep artifact
- upload-testflight: Checkout submodules with retry
- upload-testflight: Validate required secrets
- upload-testflight: Install build dependencies
- upload-testflight: Restore iOS release prep
- upload-testflight: Normalize emexDE generated Swift imports for TestFlight archive
- upload-testflight: Patch emexDE CoreCompiler Swift frontend for TestFlight archive
- upload-testflight: Apply TestFlight fast project mode
- upload-testflight: Decode App Store Connect API key
- upload-testflight: Prepare generated App Store signing assets
- upload-testflight: Install p12 signing certificate and provisioning profiles
- upload-testflight: Resolve release inputs
- upload-testflight: Identify Xcode cache compatibility
- upload-testflight: Build and upload TestFlight IPA
- upload-testflight: Commit TestFlight version bump
- repair-testflight-distribution: Repair and verify existing TestFlight distribution

### nyxian-toolchain.yml

- compiler: Resolve pinned source and host revisions
- compiler: Validate restored toolchain
- compiler: Install upstream build dependencies
- compiler: Build complete pinned upstream compiler
- compiler: Verify produced artifacts

### ios-code-mode-runtime.yml

- v8: Install build dependencies
- v8: Build jitless sandboxed V8 from pinned source
- v8: Verify complete archive

### ios-testflight-finalize.yml

- finalize-testflight: Validate required secrets
- finalize-testflight: Install dependencies
- finalize-testflight: Decode App Store Connect API key
- finalize-testflight: Finalize existing TestFlight build
