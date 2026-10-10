# Alley Cat iOS performance audit

**Revision:** October 9, 2026 (source audit on the `NightVibes33/litter` main branch)

**Validation level:** Static source review and targeted code changes. This document is **not** an on-device Instruments capture or a measured FPS/CPU baseline. A full performance sign-off requires running an updated build on the target iPhone with representative conversations and iSH projects.

## Audited paths and fixes

| Subsystem | Root cause or likely cost | Change | Risk / verification |
|---|---|---|---|
| Conversation permission refresh | `ConversationView.onChange(of: thread)` compared a whole `AppThreadSnapshot` whenever streaming updates arrived | Track a small signature of thread key and effective approval/sandbox permissions instead | Check permission updates, per-thread overrides, and rapid streaming |
| Long-chat infinite scroll | Each visibility callback built a new `turns.map(\\.id)` array, proportional to cached turn history | Cache turn ID → index when transcript turns actually change; visibility updates look up only visible IDs | Check older-history prefetch, duplicate turn IDs, and switching conversations |
| Session list | `SessionsModel` invalidated its sorted/grouped derivation by global snapshot revision, even when the session list was unchanged | Compare session summaries and reuse derived session data until summaries or filters change | Check cross-runtime lists, search, grouping, active status and archiving |
| Home | `HomeDashboardModel` reloaded thread preferences at every debounced snapshot refresh | Reload when activating the home model and on preference notifications instead | Check sync of pinned and hidden threads on return to app |
| Files workspace | `visibleEntries` sorted the entire folder on each read; counts and stats independently rescanned directory entries | Cache visible sort/filter results and statistics; invalidate on file list / sort / filter / search changes | Check big directories, rename, hidden toggle, import/delete and filters |
| Diagnostics | Synchronous per-line file writes and repeated regex compilation can block the caller during high-volume logs | Dedicated utility writer queue for low-severity lines, cached credential regexes, critical-error ordering | Verify redaction, rotated logs, crash capture and Files export |
| Sprite animations | `PetSpriteView` rebuilt atlas signatures on UI updates | Use an atlas decode revision rather than recomputing all sprite IDs | Check avatar switching and reduced-motion behavior |

## Existing protections observed in the source

- Lazy conversation rows, projected-message caching, and transcript digest handling.
- Streaming-delta coalescing and batched thread mutations in `AppModel`.
- Bounded initial/older history pagination and targeted authoritative resumption.
- Terminal output batching rather than an immediate redraw for each received chunk.
- Snapshot derivation debounce in the home and session models.

## High-cost paths that still require measurement

1. **Launch/image decode:** `home_cat.png` (~4.95 MB encoded) and `home_cat_entrance.png` (~5.55 MB encoded). Measure decoded memory, image-cache retention, first-frame latency, and peak memory before changing artwork.
2. **Large markdown/code blocks:** Markdown and syntax-highlighted blocks can be expensive during fast output. Measure long tool results, code fences, and widget-heavy chats; keep visual rendering parity.
3. **On-device build and iSH terminal:** Large Rust/LLVM/Swift builds can saturate CPU, memory, and disk. Measure app responsiveness concurrently with toolchain work; avoid introducing extra shell or process polling.
4. **Session hydration:** Test 500+ sessions from multiple runtimes while one conversation streams, including failures/reconnects.
5. **Ghostty output:** Validate large terminal floods; batching is present, but renderer and text-to-link work still need Instruments data.

## Instrumentation now available

Debug builds emit timing signposts and log lines for:
- `BuildTranscriptTurns` — transcript construction;
- `BuildTimelineProjection` — per-turn UI projection;
- `DeriveSessionList` — session grouping and sort.

Existing `PerfTracker` events include `applySnapshot`, `flushStreamingDeltas`, `OpenThread`, `SendMessage` and home refresh activity. Use Instruments **Time Profiler**, **Points of Interest**, **Core Animation**, **Allocations**, and **Hangs** on a physical device.

## Regression matrix

- Start/open/delete/rename/fork a conversation; repeat after app restart and runtime reconnect.
- Long conversation: stream 1,000+ tokens, scroll at the same time, load older pages, switch to another thread.
- Home: 100+ sessions, pins/hides, search, multiple connected runtimes, background → foreground.
- Files: navigate a folder with thousands of items, type search rapidly, change sort/filter, import/delete, revisit.
- Terminal: large command output with simultaneous chat streaming and log export.
- Runtime: start/stop on-device build while navigating the interface.

**Exit criteria:** successful iOS compile and regression tests, no missing-turn data loss, no dropped terminal output, no stale file lists, no new crashes, and measured comparison against a pre-fix build under the same load. No unmeasured percentage improvements are claimed.

**Source commits:** `83a9493c`, `01c37814`, `d17bc093`, plus this audit/cleanup commit.
