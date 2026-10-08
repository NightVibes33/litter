# App debug audit — 2026-10-08

Source baseline: 320583df, including current Settings, onboarding, typing and
StoreKit changes. This is a source and tooling audit, not a complete device
acceptance result. The execution host is Linux: Xcode and a connected iPhone
are unavailable. No native test, purchase or device success is inferred.

| Area | Evidence and remaining verification |
| --- | --- |
| Startup/onboarding | First-launch completion is persisted; replay is separate. Found disabled Files actions dismissing the tour without opening a destination. Repaired to open Advanced, including demo-folder actions. |
| Navigation | Files/Terminal default off, with Advanced toggles and home launchers. Found Files offering Terminal while disabled. Repaired to route to Advanced. Existing screen-root Pro gates are retained. |
| Chat typing | Ordinary typing avoids full-storage recoloring when skills are loaded but no mention exists. Marked keyboard composition is protected. Reported pauses still need a device reproduction/profile; this is not proof of their cause. |
| Chat/streaming | Existing leaf draft observation and cached streaming projection reduce broad invalidations. Native conversation tests and long-thread/device typing/streaming remain required. |
| Login/account | Source uses PKCE and verifies callback state. Keychain account storage is retained. Device browser callback, refresh and account switching remain required. |
| Models/local runtime | Codex 0.160.1 catalog includes GPT-6.1 Sol; account discovery determines access. Previous host suite passed 868 tests (7 ignored), Slingshot 14. These historical results were not rerun by this audit. Local V8 execution after extended-VA entitlement repair remains device-gated. |
| Purchases | Verified current nonconsumable entitlements, exact own product ID and revocations govern Pro. Files, Terminal, backgrounds and paid icons are gated; full sideload includes Pro. This is a one-time unlock, not a recurring subscription. Store product availability, sandbox buy/restore/refund remain unverified. |
| Files/Terminal | Shared workspace and terminal routes remain. UI gates precede screen tasks. CRUD, import/export, SSH trust, keyboard and terminal renderer require installed-device acceptance. |
| Icons/appearance | Paid selection checks entitlement and handles alternate-icon completion errors. Thirteen icon definitions remain. Device icon change, theme, font and wallpaper acceptance remain required. |
| Voice/Watch | Source retains native WebRTC and speaker-route handling. Actual audio meters and arbitrary-thread handoff remain incomplete per repository audit. Bluetooth, interruptions and Watch need hardware. |
| Diagnostics | Bounded redacted session files and MetricKit reports remain. Writes are synchronous; their contribution to reported pauses has not been measured. MetricKit delivery is delayed and not guaranteed. |
| Sideload tooling | KittyStore, signing, Nyxian/emexDE and BuildKit are retained in the full variant; restricted in safe TestFlight. Native archive/artifact acceptance is still pending. |
| Release/distribution | Signed build 20261007234321 uploaded, then review-metadata HTTP 409. Placeholder contact/no-sign-in defaults were removed. Exact Apple error cause and tester distribution remain unconfirmed; never reupload that IPA. |
| Android TV | Initial ARMv7 QR-login APK built. Full TV parity is still unpublished and unvalidated; Android Ghostty GLES renderer gap remains. |

Validation in this pass: all 37 Python tooling tests pass, including the real
vendored-source import-overlay regression. Diff whitespace checks pass.
A local vendored-source symlink supplies tests only and must not be committed.

Open dependency advisories and other platform limitations remain tracked in
REPOSITORY_AUDIT.md. This audit does not clear them. Native Swift XCTest,
latest signed/full unsigned archives, real Apple group states and a physical
phone walkthrough are necessary before claiming the app is fully debugged.

### File browser follow-up (2026-10-08)

Delete, Rename, and Move alerts now capture their presented item instead of
reading optional state cleared by dismissal. Single and batch deletion update
the listing only after filesystem success; failures remain visible. Rename
uses the item's parent rather than the currently displayed folder. Duplicate,
archive, and existence checks recognize dangling symlinks. Sorting now applies
the selected order to files, symlinks, and special entries alike, keeping folders
first.

Seven focused checks pass, including actual extracted shell commands deleting
files, nonempty directories, dangling links and absent paths, and duplicate/
rename collision protection. These shell checks run on Linux, not iSH.
Native Swift compilation and installed-device confirmation remain required.
Entire browser acceptance is still open for import/export, editing, extraction,
preview, concurrent operations, protected/mounted locations and failure recovery;
the alert repair is not proof of the reported device failure's sole cause.

### Extended browser pass (2026-10-08)

Reviewed listing/filtering/sorting, navigation and shortcuts, creation, single/
batch deletion, rename/move/duplicate/compress, extraction, import, sharing,
text/image preview and editor saving. Additional repaired paths:

- Sharing uses a unique host directory per export, retaining same-name exports.
  Each decoded chunk must match the expected length; short reads fail instead
  of returning a corrupt file. Cancellation removes incomplete host output.
- Directory sharing removes its fakefs temporary archive on copy failure too.
- Non-overwriting imports reject dangling symlink destinations. File writes
  check cancellation before committing. Replacement rejects directories and
  symlinks rather than moving a temporary file into a folder or destroying a
  link; editing a symlink reports an error instead of silently replacing it.
- Folder symlinks navigate to their directory.
- The editor prevents editing after a failed load and while saving, captures the
  saved text, and confirms unsaved dismissal.
- Move requires an existing destination directory; duplicate and compress
  resolve names in the source item's folder, retaining that folder across awaits.

Nine focused checks pass. Native/archive acceptance remains pending. Device
coverage must include mounted-location permissions, same-name shares, large
files, interrupted writes, link previews, and unsaved dismissal. The current
tab/newline-delimited listing cannot faithfully represent filenames containing
tabs/newlines. Archive extraction still depends on installed fakefs tools.
These limits are recorded rather than described as verified functionality.

### Listing, extraction and directory import follow-up

Directory listing now encodes names, paths and link targets independently, so
tabs/newlines round-trip; glob enumeration includes broken links and checks
directory access before listing. Eleven focused tests pass, including actual
listing commands with unusual names and gzip extraction into the requested
directory without deleting the source or overwriting an existing output.
Extraction resolves its destination beside the selected archive and reports
empty-output failures. Folder import propagates enumeration errors, exclusively
creates its destination, and removes partial newly created imports on failure
or cancellation.

Signed run 37707587937 uploaded build 20261008004054 (fdd239 source).
Authenticated job logs show VALID, internal IN_BETA_TESTING, external
WAITING_FOR_BETA_REVIEW; both groups have one tester and are assigned. This
build predates the latest browser fixes. Native verification of these newer
changes and complete physical-device browser acceptance remain pending.
