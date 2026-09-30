# Upstream runtime integration status

This branch adapts upstream tool-event fixes and imports the Sol 6.1/Terra 5.6 model catalog while preserving Alley Cãt's existing app views, assets, themes, identity, and embedded KittyStore interface.

Litter upstream reviewed: `7a55092c61a779f35c3b9b35f4e1907eb9257205`. Three runtime fixes are integrated: `16eea3e6` normalizes legacy tool lifecycle notifications before strict decode, `b2d47c42` refreshes authoritative tool results after idle notifications, and `665cc00a` preserves live tool items omitted from replay. The JSON-line wire retains this fork's explicit Send-future interface.

The Codex catalog patch imports `gpt-6.1-sol` and refreshes `gpt-5.6-terra` from OpenAI Codex `90abcfac02665ad882853a04155591cd863b2ca7`. The pinned schema requires `base_instructions`; the upstream instruction template supplies this compatibility field. Model capabilities and reasoning levels come from upstream. The patch is applied after the existing aggregate Astra bridge patch and does not require a separate submodule commit or push.

Nyxian's existing source revision now includes its recursive LLVM-On-iOS, TrollStore, and ChOma sources. Imports use exact gitlinks, preserve the existing compiler compatibility overlays, validate in a staging directory, and replace the destination only after validation. Historical focused-import metadata is explicitly marked superseded. The embedded emexDE module and its LLVM dependency are separate from this BuildKit snapshot and remain pinned to their recorded gitlinks.

KittyStore's existing SideStore/Feather source snapshots and nested dependencies are verified. Both RustBridge and minimuxer device/simulator builds now require committed Cargo lockfiles and use `--locked`. Native libplist, libimobiledevice-glue, libtatsu, libusbmuxd, and libimobiledevice sources are pinned as recursive submodules under `ThirdParty/SideStore/NativeDependencies`. `NATIVE_DEPENDENCIES.json` records their exact revisions; both vendored native build scripts use those local checkouts and reject revision mismatches and autogen failures. Native artifact caches include the source pins and wrapper changes.

Run `make upstream-dependencies-verify`, `sh tools/scripts/verify-nyxian-source-import.sh`, and `bash tools/scripts/verify-kittystore-integration.sh` for source checks. They validate checkout readiness, recorded submodule revisions, populated snapshot dependencies, local Cargo paths, lockfiles, and Swift package revisions. They cannot establish that SDKs, downloaded native support binaries, signing services, VPN transport, or device execution work.

This is a staged integration, not a full merge of every later upstream revision. At initial review Litter had 225 upstream-only commits, with major UI and architecture changes. The newer emexDE/Nyxian head `3678a9c6612824c4234e9b98dc25687c46401687` changes 383 files relative to the embedded module; SideStore head `0dd743f75afc358b0ba4a002feb5f19474492371` also remains unintegrated. Those upgrades require compatible adaptations and macOS/Xcode validation before replacing the working pins.

Remaining release validation: compile the full sideload IPA with Xcode, exercise Terra 5.6 and Sol 6.1 tool calls with an authorized account, run a Nyxian Swift/IPA job on device, and verify KittyStore signing/install/refresh using LocalDevVPN. This Linux environment cannot perform those iOS checks. Catalog inclusion does not grant model access to an account.

The shared mobile runtime test fixtures are aligned to the pinned Codex protocol (optional client/environment IDs, path wrappers, plugin metadata, thread metadata, and new item kinds). The suite passes with 757 tests and five existing ignored tests; fixture updates preserve the assertions and do not change the app UI.

### Interrupt recovery follow-up

Adapted upstream `da7bf861af790d2752a1d6439527ea5f96fe0299` to the fork's
recorded protocol: an acknowledged interrupt clears the matching active turn
locally and broadcasts completion so later messages reach the host. Regression
coverage checks missing host completion, duplicate completion, and a late old
completion after a newer turn starts. The upstream test fixtures use newer
request fields; those fixtures were adapted to the existing protocol.

The first GitHub runtime check exposed parallel cloud-sync tests resetting the
same process-wide preference table. The tests now hold a shared test mutex for
the complete scenario; production preference synchronization is unchanged.
The matching-turn completion guard is adapted from upstream `e051f104`.
Follow-up validation: 760 shared-runtime tests passed, 5 existing live-host tests
ignored; dependency source closure and whitespace checks passed.

### Xcode validation without publishing

The unsigned iOS workflow accepts `publish_release: false` (the manual default).
It builds and uploads the IPA as an Actions artifact while skipping release
creation and stable KittyStore/AltStore source updates. Push builds on main
retain the existing publication behavior. Use `build_mode: full-sideload` on
the integration branch to validate the embedded frameworks and KittyStore.

SideStore's native build also had an unbounded loop searching for a vendored
OpenSSL installation. Discovery now waits at most five minutes for Cargo's
concurrent OpenSSL build, then reports the searched directory and target.
This avoids indefinitely stalled KittyStore builds when OpenSSL is missing.

Latest SideStore `0dd743f75afc358b0ba4a002feb5f19474492371` replaces AltSign with
SideSign and updates minimuxer while removing several old native submodules.
The existing embedded KittyStore still uses AltSign; replacing that snapshot
alone would remove dependencies required by its current build. The signing engine has since been adapted through the boundary described below.
Nyxian's coordinated newer compiler/LLVM API migration remains outstanding. Neither latest revision is marked integrated.

### Further runtime and signing integration

Additional adapted runtime fixes: `a8fb7bfb` routes interrupts to their owning
runtime and retains new/active threads omitted by a list page; `d25bbca2` bounds
thread-opening RPCs and parallelizes reconnect/account probes. Model picker
cache behavior already matched `abee3ace`; its regression coverage is now
included. Realtime item-boundary behavior from `700a2eca` was already present.

The SideSign engine from SideStore's latest recorded revision is now imported
in full at `6b68651697f99791ef85404b7aea1891a26a285d`. Its four moving package
branches are pinned to its upstream resolved revisions. A data-only adapter
connects host signing and embedded KittyStore resigning to the new engine while
retaining AltSign's existing account and Objective-C model boundary. Both the
upstream signer tests and adapter smoke tests run in a macOS CI job. Their tests passed in run `36682706245` and again after the compatible Unicorn rebuild
in run `36686776755`; full iOS compile validation is pending; this change is not yet
release-ready. The latest minimuxer/pairing architecture is still outstanding.

Latest ProjectNyxian head reviewed: `de9cec58b50af005e5a949f811829a062c8e3e88`.
Its guarded-process-access bypass and credential-modification paths are excluded
from this work. The newer compiler APIs and Swift 6.4 toolchain still need
compatible integration; the existing BuildKit and embedded compiler pins have
not been relabeled as upgraded.

The root XcodeGen package declarations now freeze existing moving branches and
open-ended version ranges to their already recorded revisions/versions. This
prevents adding SideSign from silently upgrading UI packages during dependency
resolution. The app's package versions are preserved.

Networking dependency adaptation from `49bc1514` uses exact Iroh `1.0.3` and
Russh `0.62.6`, including the new embedded TLS-root configuration API. With the
new lockfile, all 767 shared-runtime tests pass (five live-host tests ignored).
The signing adapter smoke test also creates a disposable local RSA identity,
CMS provisioning profile, and compiled test app, then signs that app through
the adapter and verifies its embedded profile, resource seal, and completed
progress. It does not use user credentials or contact Apple's portal.

The existing unsigned iOS lane substitutes a Swift frontend implementation that
returns failure because matching generated Swift compiler headers are not
available in its support artifact set. A successful archive alone therefore
cannot establish working on-device Swift compilation. Replacing that fallback
with the real frontend and matching generated headers remains necessary before
claiming full Nyxian compiler support.

### Unicorn deployment compatibility

The pinned AnisetteKit release artifact contains iOS objects requiring iOS 26.5. KittyStore instead builds Unicorn source `a53ddc9ac6d65b24936d4a37917333fcd816cfd0` with the software interpreter for iOS 18 and macOS 12. AnisetteKit is imported at `db8b41022697b6c19be8a5f01a1ce834145a2a26` and consumes the generated local XCFramework. The build checks actual object deployment metadata; it does not relabel downloaded binaries. Run `36686776755` rebuilt all three platform slices, verified their object deployment targets, and passed five SideSign tests plus two adapter tests, including local app signing. The full iOS archive still needs independent validation.

### Signer linkage ownership

Full archive run `36686792856` rejected duplicate static SideSign linkage from Litter and SideStore. The SideStore framework now owns the signer and adapter; Litter calls its public data-only adapter and does not link SideSign directly. The adapter smoke tests import its module through the public boundary. Full archive validation must be repeated with this correction.

### New minimuxer dependency audit

The complete direct/local package graph at `12be70dc2627307a16bfd2dc7a009080d5bec909` introduces Common, DeviceGateway, pinned-to-be RemotePairingKit, and four native artifacts. All four artifact checksums were verified against their manifests. Actual Mach-O object metadata shows EMProxy and IDevice simulator slices require iOS 26.5 and omit x86_64; libimobiledevice and OpenSSL device/simulator deployment targets fit iOS 18. RemotePairingKit also introduces an OpenSSL target colliding with retained AltSign. The new async API lacks the existing installed-app enumeration method, which must be preserved during migration. Exact artifacts, revisions, and requirements are recorded in `minimuxer-next-dependency-audit.json`; the incompatible graph has not been wired into the app.

The optional `next_minimuxer_native_only` runtime workflow builds EMProxy source `6e117e140ca7cff4ff106bdefa18147552a0e592` and IDevice source `3e55c8486b2057e40c1f74aaaa1155c82341cf76` using their committed Cargo locks and recursive source dependencies. It explicitly targets iOS 18 for device and both simulator architectures, creates XCFrameworks, and verifies actual object deployment metadata. The resulting artifacts are for the coordinated async API migration; they do not replace the current transport automatically.
