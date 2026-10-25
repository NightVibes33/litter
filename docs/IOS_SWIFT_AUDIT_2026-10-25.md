# iOS Swift audit — 2026-10-25

Baseline: `42121c431115caf2f3ad70aba35d753d78adf248`.

## Scope and method

The inventory includes 319 first-party Swift, Objective-C and bridge source/test
files under `apps/ios`, including the app, embedded hosts, Watch and Live Activity
targets. Generated bindings and vendored third-party implementations are outside
this inventory. Source inspection and targeted searches cover lifecycle,
collection identity, cancellation, persistence, media, interop and concurrency.
This is not a claim that every runtime path or third-party dependency is proven.

Applied skills: Swift architecture, SwiftUI expert/performance, Swift concurrency,
UIKit interop, debugging/Instruments, AVKit and Swift testing. The app currently
builds in Swift 5.9 mode with targeted concurrency; embedded targets have their
own settings. A global Swift 6 migration is not included in these fixes.

## Review checklist

- [x] Startup, termination, foreground/background and main-actor blocking.
- [x] Chat rendering, session projections, scrolling, replayed IDs and collapse state.
- [x] Keyboard focus, UIKit representable teardown and delayed task cancellation.
- [x] Authentication callbacks, continuation lifetime and stale-attempt callbacks.
- [x] Downloads, pre-start cancellation and HTTP error responses.
- [x] Persistence and nullable Core Data dictionary result handling.
- [x] Dictation buffers, microphone format/startup failure, meter synchronization.
- [x] Wallpaper playback/looper teardown and PiP/Watch projection boundaries.
- [x] Embedded signing/store/runtime bridges inspected for casts and blocking calls.
- [x] Focused regression tests added; independent Swift syntax CI added.
- [ ] Native build and new XCTest/XCUITest results for this audit commit.
- [ ] Release build on iPhone 16, iOS 27.0.1: keyboard show/hide, rapid typing,
      long transcripts, sheets, back navigation and app switching.
- [ ] Hardware verification of microphone interruption/route changes, WebRTC,
      PiP, Watch synchronization, pairing, signing and embedded runtime execution.

## Fixed source findings

| Area | Failure mechanism | Change |
| --- | --- | --- |
| Termination | Main thread waited for a task scheduled on the same MainActor | Resolve client before detached best-effort shutdown; remove semaphore wait |
| Chat and sessions | Duplicate IDs trapped in dictionary construction | Explicit first/latest policies for render lookups; disambiguate colliding transcript targets |
| Focus | Cancelled sleep continued into keyboard state writes | Return on cancellation in Home, search and quick-reply focus tasks |
| OAuth | Repeated query names trapped; stop discarded continuations; stale session callbacks could affect replacement login | Reject ambiguous parameters, resume stopped waiters, scope callbacks to their server |
| Downloads | Cancellation before task installation was lost; state raced cancellation; HTTP error bodies were saved as files | Lock start/cancel/completion state, preserve cancellation, reject non-success HTTP status |
| Diagnostics | Main-thread warning/error drained queued disk writes | UI logging stays queued, preserving serial order; explicit drain remains available |
| Dictation | Invalid input format could trigger installTap assertions; failed startup retained resources; callback buffers were reused | Validate format, clean failed startup, copy mono samples, encode WAV off the main actor, lock meter throttle, clear cancelled buffers |
| Store refresh | Nullable dictionary fields failed forced String casts; build version comparison discarded actual value | Read typed optional fields from Any-valued rows and preserve the build version |
| Video wallpaper | Old looper still managed items removed during replacement | Disable looping before clearing/rebuilding player queue |

## Validation and limits

Local `git diff --check` passes. CI at `4ed805b` parsed 314 Swift files with
zero syntax failures. The isolated encoder package initially omitted its macOS
minimum and failed an availability check; the package now targets macOS 14.
At `a51e6fe`, all 314 Swift files parsed and all four isolated encoder tests
passed on Xcode 26.3. Native app tests remain pending. This execution environment
has no Xcode or Swift
compiler; native compilation and simulator execution are delegated to CI.
The new independent syntax job is explicitly not a substitute for type checking,
XCTest, UI tests or hardware acceptance. Existing Mobile CI also runs the shared
Rust tests before producing its iOS build prerequisites; failures there remain
visible and must not be confused with native iOS test results.

Existing hard-coded regex/URL assertions and programmatic-only coder initializers
were reviewed rather than blanket-replaced. The remaining unique-key OAuth and
transcript lookups now have explicit uniqueness checks before construction.
StoreKit product lookup relies on the product API's unique product identifiers.
Security framework casts remain at their typed framework boundary.

## Remaining measured-work requirements

No Instruments trace was supplied or captured, and no physical device is attached
here. There is no measured before/after CPU, memory, latency or crash-free rate.
Some image/theme rendering still runs synchronously and warrants a Release
Time Profiler/Allocations pass. Unbounded recording memory,
full Swift 6 concurrency adoption, third-party embedded framework internals and
shared Rust behavior remain separate acceptance work; no blanket safety claim is
made by this source pass.
