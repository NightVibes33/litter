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
- Verified unsigned IPA workflow green for commit `9c78f95df9b9e10ec54c2038bfab7e35421d1730` in run `25630987712`.

- Added host staging bridge because native iOS code cannot directly read `/root` in iSH fakefs.
- Added optional in-process Nyxian driver source and build-script mode for private BuildKit-enabled IPAs.
- Added fakefs environment report/bootstrap commands for bot-readable diagnostics and repair.

- Added fakefs-backed iOS Files imports for files, folders, images, ZIP/RAR/TAR-style archives, and chat composer attachment path mentions.
- Added image preview and archive extraction actions in the local file workspace.
- Added clickable Hugging Face model detail sheets with GGUF sibling download cards and persistent download/install progress.

- Added `litter-nyxian-status` and Settings -> BuildKit readiness rows for direct Swift execution and unsigned IPA capability.
- Added `tools/scripts/vendor-nyxian.sh`, `tools/scripts/build-nyxian-buildkit-assets.sh`, and `tools/scripts/verify-nyxian-buildkit-assets.sh` plus make targets.
- Changed private asset packaging default to in-process native mode to avoid fake-ready runner manifests with no runner executable.
- Added a minimal in-process IPA packager to `LitterBuildKitInProcess.mm` and artifact metadata export so generated IPAs are copied back into `/root/builds/<job-id>`.
- Stabilized the fast BuildKit-focused Nyxian import path after iSH network timeouts, restored tracked metadata, excluded heavy/irrelevant upstream assets, and recorded `ThirdParty/Nyxian/VENDOR_LOCK.json`.
