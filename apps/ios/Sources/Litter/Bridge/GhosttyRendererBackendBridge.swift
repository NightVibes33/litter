import Foundation

/// Thin Swift implementation of the Rust-defined `TerminalRendererBackend`
/// callback interface. Holds a weak reference to the platform-side
/// `LitterGhosttyTerminal` and hops every Ghostty C call onto the main
/// thread (Ghostty's surface APIs are not thread-safe). The Rust tick task
/// invokes these methods on the shared tokio runtime.
///
/// Selection state lives here because Ghostty's C surface doesn't expose a
/// public setter for the painted selection range — the platform paints the
/// overlay itself and uses the stored range to satisfy `readSelection` via
/// `ghostty_surface_read_text`. The UI overlay view subscribes to
/// `onSelectionRangeChanged` to redraw handles when Rust pushes a new range.
final class GhosttyRendererBackendBridge: TerminalRendererBackend, @unchecked Sendable {
    private weak var terminal: LitterGhosttyTerminal?

    /// Most recently pushed selection range (viewport-relative). `nil` when
    /// no selection is active. Written from the Rust runtime via
    /// `setSelectionOverlay` and read from the main thread by the overlay
    /// view + edit menu. Guarded by `selectionLock` to keep the write/read
    /// race safe — the storage is a single optional, no fancy state.
    private let selectionLock = NSLock()
    private var selectionRange: TerminalCellRange?

    /// Callback fired on the main thread whenever the stored selection
    /// range changes. The terminal view installs this to drive handle
    /// repaints + edit-menu visibility.
    var onSelectionRangeChanged: ((TerminalCellRange?) -> Void)?

    init(terminal: LitterGhosttyTerminal) {
        self.terminal = terminal
    }

    func setFocus(focused: Bool) {
        let terminal = self.terminal
        DispatchQueue.main.async {
            terminal?.setFocused(focused)
        }
    }

    func setOcclusion(occluded: Bool) {
        let terminal = self.terminal
        DispatchQueue.main.async {
            terminal?.setOcclusion(occluded)
        }
    }

    func requestRedraw() {
        // UIKit Ghostty surfaces render through Ghostty's own renderer thread.
        // Ghostty's wakeup callback drains the app mailbox; this Rust-side
        // renderer callback only exists for Android's app-thread EGL path.
    }

    func applyConfigFile(path: String) {
        let terminal = self.terminal
        if Thread.isMainThread {
            try? terminal?.applyConfig(atPath: path)
        } else {
            DispatchQueue.main.async {
                try? terminal?.applyConfig(atPath: path)
            }
        }
    }

    func dispatchKey(event: TerminalKeyEvent) {
        let terminal = self.terminal
        let action = Int32(GhosttyKeyTranslator.action(for: event.action))
        let litterKey = GhosttyKeyTranslator.litterKey(for: event.code)
        let mods = Int32(GhosttyKeyTranslator.mods(for: event.mods))
        let text = event.text.isEmpty ? nil : event.text
        DispatchQueue.main.async {
            _ = terminal?.dispatchKeyAction(
                action,
                key: litterKey,
                mods: mods,
                text: text,
                composing: false
            )
        }
    }

    func dispatchText(text: String, composing: Bool) {
        let terminal = self.terminal
        DispatchQueue.main.async {
            if composing {
                terminal?.setPreeditText(text.isEmpty ? nil : text)
            } else {
                terminal?.sendText(text)
            }
        }
    }

    func dispatchPaste(bytes: Data) {
        // Bracketed-paste bytes must travel PTY-input direction
        // (terminal → shell), not PTY-output direction. The terminal's
        // `inputHandler` is the same closure Ghostty's
        // `external_pty_write` ultimately fires when the user types, so
        // we reuse it: the platform-side controller forwards the bytes
        // to the running process unchanged. Writing them through
        // `writeOutput` would paint the wrapper on screen instead.
        let terminal = self.terminal
        DispatchQueue.main.async {
            terminal?.inputHandler?(bytes)
        }
    }

    func readSelection() -> String? {
        let range = currentSelectionRange()
        guard let range else { return nil }
        // `read_text` must run on the same thread as other Ghostty surface
        // calls. We're invoked from the Rust tick task, so hop to main and
        // block long enough to return — bounded waits keep this safe under
        // a misbehaving renderer (no deadlock with the renderer's tokio
        // runtime because no main-thread caller is waiting on us).
        return runOnMainBlocking { [weak terminal] in
            terminal?.readText(
                fromRow: range.start.row,
                column: range.start.col,
                toRow: range.end.row,
                column: range.end.col
            )
        }
    }

    func readText(startRow: UInt32, startCol: UInt32, endRow: UInt32, endCol: UInt32) -> String? {
        runOnMainBlocking { [weak terminal] in
            terminal?.readText(
                fromRow: startRow,
                column: startCol,
                toRow: endRow,
                column: endCol
            )
        }
    }

    func cellMetrics() -> TerminalCellMetrics {
        let metrics = runOnMainBlocking { [weak terminal] in
            terminal?.surfaceMetrics()
        } ?? LitterGhosttySurfaceMetrics()
        return TerminalCellMetrics(
            cellWidthPx: Float(metrics.cellWidthPx),
            cellHeightPx: Float(metrics.cellHeightPx),
            cols: UInt32(metrics.columns),
            rows: UInt32(metrics.rows),
            // Viewport-relative selection: top-left of the visible area is
            // always row 0 in our coordinate system. Scrollback rows live
            // outside the viewport and aren't selectable through long-press
            // yet — the OSC parser's absolute-row tracking is separate.
            viewportTop: 0
        )
    }

    func setSelectionOverlay(range: TerminalCellRange?) {
        selectionLock.lock()
        selectionRange = range
        selectionLock.unlock()
        let callback = onSelectionRangeChanged
        DispatchQueue.main.async {
            callback?(range)
        }
    }

    /// Snapshot the current selection range. Used by `readSelection` and
    /// by the overlay view via `currentRange` to repaint.
    func currentSelectionRange() -> TerminalCellRange? {
        selectionLock.lock()
        defer { selectionLock.unlock() }
        return selectionRange
    }

    /// Run `work` on the main thread synchronously, returning its result.
    /// If we're already on main, runs inline; otherwise dispatches and
    /// waits. `DispatchQueue.main.sync` from a background thread is fine
    /// here because the Rust tick task never holds a lock the main thread
    /// could be waiting on.
    private func runOnMainBlocking<T>(_ work: @MainActor @Sendable () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { work() }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { work() }
        }
    }
}

/// Translation: Rust `TerminalKey*` → bridge-level `LitterGhosttyKey`.
/// Bridge does the final Ghostty-enum mapping in Obj-C.
enum GhosttyKeyTranslator {
    static func action(for value: TerminalKeyAction) -> Int {
        switch value {
        case .release: return 0
        case .press: return 1
        case .repeat: return 2
        }
    }

    static func mods(for value: TerminalKeyMods) -> Int {
        var bits = 0
        if value.shift { bits |= 1 << 0 }
        if value.ctrl { bits |= 1 << 1 }
        if value.alt { bits |= 1 << 2 }
        if value.meta { bits |= 1 << 3 }
        return bits
    }

    static func litterKey(for value: TerminalKeyCode) -> LitterGhosttyKey {
        switch value {
        case .enter: return .enter
        case .tab: return .tab
        case .backspace: return .backspace
        case .escape: return .escape
        case .space: return .space
        case .arrowUp: return .arrowUp
        case .arrowDown: return .arrowDown
        case .arrowLeft: return .arrowLeft
        case .arrowRight: return .arrowRight
        case .pageUp: return .pageUp
        case .pageDown: return .pageDown
        case .home: return .home
        case .end: return .end
        case .delete: return .delete
        case .insert: return .insert
        default: return .unidentified
        }
    }
}
