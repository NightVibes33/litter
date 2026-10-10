# Alley Cat iOS upstream/performance parity audit

Audit baseline: upstream `0xSero/litter` at `366aefdd616f16b9efb6c888be6cfd916bda47d6`.
Alley Cat branch: `NightVibes33/litter/main`. Generated 2026-10-09.
This is a source audit, not a device-time profile. Rerun the parity comparison after
every upstream update and run Instruments on each distribution.

## Distribution contract

| Feature | Upstream Litter | TestFlight | Full unsigned sideload |
| --- | --- | --- | --- |
| Chat, thread persistence, streaming, UI rendering | Canonical | Preserve upstream | Same shared implementation |
| Native terminal/iSH and connected runtimes | Canonical | Preserve upstream | Same shared implementation |
| Alley Cat identity and in-app Pro entitlement | n/a | Added | Added; unlocked by sideload compile condition when configured |
| KittyStore/SideStore signing | n/a | Not linked; cannot bootstrap | Embedded in full sideload |
| Nyxian/emexDE compiler and BuildKit extensions | n/a | Not linked; no BuildKit request monitor | Embedded in full sideload |
| Files diagnostics and error recovery | n/a | Retained | Retained |

The TestFlight project patch (`tools/scripts/patch-ios-testflight-fast-project.py`)
strips sideload-only targets and adds `-DLITTER_APP_STORE_SAFE`. This change
also prevents the BuildKit fakefs request monitor from starting in that build.
The unsigned-IPA workflow retains the full compiler/Store integrations.

## Verified differences, not equivalence claims

The 2026-10-09 tree comparison found **469 shared iOS files**, of which **91
differed** (including project configuration, branding, chat fixes, and added
capabilities). Most upstream chat rendering files are identical; the fork is
**not** byte-for-byte identical to Litter. Do not blindly copy upstream
`project.yml` over this fork: it would remove distribution targets and
Alley Cat signing configuration. Keep core changes minimal and gated.

## Potential bottlenecks and disposition

| Area | Observation | Status / validation |
| --- | --- | --- |
| Full Rust snapshot | Upstream historical benchmark: 1,000 threads x 200 items, 132 ms median and 265 MB allocated | Added metadata-only slow-fetch/apply logging; structural snapshot reduction remains future work |
| Chat transcript and home scrolling | Large item arrays and full-state invalidation can hitch | Upstream incremental cache remains; fork already has targeted 2026-10-09 UI fixes; verify hitches on hardware |
| Debug/info logging | Custom files writer previously performed synchronous work on the UI hot path | Recent fork commit `d17bc0933` moved noncritical writes to a serial utility queue, caches regex rules |
| Large Files workspace | Sorting and toolbar aggregates can rescan large directories | Recent fork commit `01c37814f` adds caching; verify after filesystem mutations |
| Pet animation | Atlas-frame signature used repeated per-frame work | Recent fork commit `d17bc0933` uses an atlas revision |
| BuildKit fakefs monitor | 2-second polling loop was enabled even in TestFlight without Nyxian | Now limited to sideloads embedding the compiler |
| Background/foreground | Concurrent reconnection, rehydration, and duplicated snapshot refresh can delay UI | Compare network traces; avoid removing upstream recovery paths without tests |
| Images & attachments | Large raster decode or attachment conversion can cause UI hitches | ImageIO thumbnail decode is already off-main; validate attachment encode and peak memory |
| Subscription and purchase restore | StoreKit is separate from chat | Keep entitlement flow restricted to TestFlight/App Store configurations and measure cold-start network behavior |

The upstream `docs/PERFORMANCE_PROFILE.md` timings are historical measurements,
not Alley Cat latest-build results.

## On-device acceptance checks

1. Record Instruments **Time Profiler**, **Hitches**, **Allocations**, **SwiftUI**
   while launching, opening a 1,000-message chat, scrolling, streaming,
   backgrounding and resuming. Watch `OpenThread`, `SendMessage`, and
   `HomeDashboardModel.refreshState` signposts.
2. Export `Files > Alley Cat > Diagnostics`; verify any
   `slow full snapshot refresh` records contain only counts and durations.
3. TestFlight: no KittyStore, Nyxian, fakefs monitor, or sideload Pro unlock.
   Core chat/terminal/navigation continue to work.
4. Full unsigned IPA: signing, Nyxian, monitor and standard chat all work;
   stop/restart the app and verify thread deletion and resumption.
5. CI: require valid unsigned-IPA and TestFlight builds. Do not infer a green
   build or measured speedup from a successful commit.

## Remaining high-risk work

- Snapshot projection can allocate proportional to full conversation history;
  a structural change to the shared Rust reducer should be implemented **in
  upstream Litter first**, with benchmark comparisons, rather than a divergent
  Alley Cat-only chat store.
- Validate the complete TestFlight binary after pruning: source-level flags
  must match linked frameworks, entitlements and release artifact manifests.
- Establish cold launch p50/p95, tap-to-open p95, memory high-water mark and
  dropped-frame counts from real iPhone/iPad builds. These are not available
  from a GitHub source comparison alone.
