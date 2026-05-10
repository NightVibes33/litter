# Debug Log

## 2026-05-10

- Confirmed the public unsigned IPA workflow is green on `main` before private BuildKit work.
- Confirmed current BuildKit only had Nyxian source import and command queueing, not a callable compiler backend.
- Added a private BuildKit asset-pack contract instead of committing Apple SDK files.
- Added fakefs repair for `/dev/null`, `/dev/random`, `/dev/urandom`, `/tmp`, `/var/tmp`, `/usr/local/bin`, and `/root/builds`.
- Added `litter-fs-doctor` so agents can validate Git temp-file readiness and core fakefs paths.
- Added native driver ABI docs for `LitterBuildKitNative.framework`.

- Added source/build script for the native BuildKit ABI wrapper and runner delegation contract.
- Added Settings -> BuildKit folder import so users can install expanded private asset bundles without rebuilding the IPA.
- Extended BuildKit manifests/status checks to validate an optional Nyxian runner path.
