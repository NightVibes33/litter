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
