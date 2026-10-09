# Litter upstream reconciliation — 2026-10-09

Compared published fork d5b8944a with 0xSero/litter main
366aefdd616f16b9efb6c888be6cfd916bda47d6. The upstream commit is an
ancestor of this fork; missing upstream commits were not demonstrated.

The fork selects Codex 0.160.1 through the root sync script, rather than
upstream Litter's recorded Codex checkout be2951ea. Mobile API adapters,
local iSH execution, jitless V8, account recovery and embedded integrations
therefore need compatibility validation in addition to UI comparison.

## Thread lifecycle repair

Pinned Codex emits thread/closed after unloading a thread. Published Litter
previously ignored that notification, leaving both the direct resume marker
and store is_resumed state set. The shared client now invalidates both on
close, retains the thread and transcript, and resumes an unloaded stored
thread before starting its next turn. Archive notifications invalidate the
subscription marker and still remove the archived thread from the store.
Successful start/resume/fork responses mark their snapshots loaded, so a
fresh chat does not require another resume before its first turn. Runtime
routes survive unload. No missing thread is replaced with an empty
chat, no archive error is treated as success, and no mutating request is
blindly retried.

The iOS delete confirmation retains its presented target through dismissal
and uses upstream's original wording. The operation remains upstream's
thread/archive; this change does not introduce permanent-deletion semantics.

This repairs a demonstrable lifecycle gap, not proof of every reported
thread-not-found cause. The user's installed build number is unknown.
Native CI and device validation must cover idle reopen/send, archive after
idle, empty chat archive, account switching, reconnect, and multiple runtimes.

## Preserved scope and open acceptance

Alley Cãt branding, KittyStore/SideStore, Nyxian/emexDE, BuildKit, all icon
choices, themes, onboarding, authenticated models, and the signed-safe/full
sideload distinction remain. No source pin or submodule gitlink is changed.

The read-only audit also identified fork-specific account recovery, local
execution, filesystem, synchronous diagnostics and background push behavior.
These are compatibility investigation areas, not automatically proven bugs
and not authorization to discard the integrations.

At the last dispatch attempt GitHub reported Actions disabled for this
repository. Workflow files being active does not establish runner availability.
No installed update, IPA or TestFlight distribution is inferred from host checks.

## Host verification

Final locked all-targets mobile compilation passed. The mobile library suite
passed 875 tests with seven ignored and no failures; Slingshot passed all 14
library tests. All 80 Python tooling tests passed. Lifecycle tests cover typed
close notification identity, subscription invalidation, history retention,
archive removal, and resume-before-send after server unload. Existing fresh
thread reconciliation also asserts its loaded state. Diff whitespace checks
passed. Public UniFFI request and snapshot layouts are unchanged; native CI
still needs to regenerate bindings and validate both platform builds.

The separate validation workspace was restored after the checks. Temporary
vendored-source symlinks used by tooling tests were removed. No gitlinks,
source pins, dependencies, signing settings or embedded integration files
are part of this repair.
