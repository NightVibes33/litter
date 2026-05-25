package com.litter.android.ui.terminal

import android.os.Handler
import android.os.Looper
import com.litter.android.core.bridge.GhosttyRendererBridge
import uniffi.codex_mobile_client.TerminalCellMetrics
import uniffi.codex_mobile_client.TerminalCellRange
import uniffi.codex_mobile_client.TerminalKeyAction
import uniffi.codex_mobile_client.TerminalKeyCode
import uniffi.codex_mobile_client.TerminalKeyEvent
import uniffi.codex_mobile_client.TerminalKeyMods
import uniffi.codex_mobile_client.TerminalRendererBackend
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicReference

/**
 * Kotlin implementation of the Rust-defined `TerminalRendererBackend` callback
 * interface. The Rust [`uniffi.codex_mobile_client.TerminalRenderer`] tick task
 * invokes these methods from a tokio worker; we hop to the main thread before
 * touching the (non-thread-safe) Ghostty surface APIs.
 *
 * Selection state lives here because Ghostty's C surface doesn't expose a
 * public setter for the painted overlay — the platform paints handles
 * itself and uses the stored range to satisfy `readSelection` via
 * `nativeReadText`. The Compose overlay subscribes to
 * [`onSelectionRangeChanged`] to redraw when Rust pushes a new range.
 */
internal class GhosttyRendererBackendBridge(
    private val surface: GhosttyRendererBridge.GhosttyRendererSurface,
    private val onRequestRedraw: () -> Unit,
    /// Closure invoked when the renderer needs to push raw bytes to the
    /// PTY input direction (terminal → shell). Bracketed-paste payloads
    /// flow through here so they reach the running process unmodified.
    private val onPasteBytes: (ByteArray) -> Unit,
) : TerminalRendererBackend {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val selectionRange = AtomicReference<TerminalCellRange?>(null)

    /// Main-thread callback fired whenever the stored selection range
    /// changes. The terminal surface installs this to drive handle
    /// repaints + ActionMode visibility.
    @Volatile
    var onSelectionRangeChanged: ((TerminalCellRange?) -> Unit)? = null

    override fun setFocus(focused: Boolean) {
        runOnMain { surface.setFocus(focused) }
    }

    override fun setOcclusion(occluded: Boolean) {
        runOnMain { surface.setOcclusion(occluded) }
    }

    override fun requestRedraw() {
        runOnMain { onRequestRedraw() }
    }

    override fun applyConfigFile(path: String) {
        runOnMainBlocking {
            surface.applyConfig(path)
            onRequestRedraw()
            true
        }
    }

    override fun dispatchKey(event: TerminalKeyEvent) {
        val action = when (event.action) {
            TerminalKeyAction.RELEASE -> 0
            TerminalKeyAction.PRESS -> 1
            TerminalKeyAction.REPEAT -> 2
        }
        val key = bridgeKey(event.code)
        val mods = packMods(event.mods)
        val text = event.text.ifEmpty { null }
        runOnMain { surface.sendKey(action, key, mods, text, composing = false) }
    }

    override fun dispatchText(text: String, composing: Boolean) {
        runOnMain {
            if (composing) {
                surface.sendPreedit(text.ifEmpty { null })
            } else if (text.isNotEmpty()) {
                surface.sendText(text)
            }
        }
    }

    override fun dispatchPaste(bytes: ByteArray) {
        // Bracketed-paste bytes must travel PTY-input direction (terminal
        // → shell), so we feed them through the same callback Ghostty's
        // `external_pty_write` triggers on key input. `surface.write`
        // would route them PTY-output direction (paint), which is wrong.
        runOnMain { onPasteBytes(bytes) }
    }

    override fun readSelection(): String? {
        val range = selectionRange.get() ?: return null
        return readTextBlocking(
            startRow = range.start.row.toInt(),
            startCol = range.start.col.toInt(),
            endRow = range.end.row.toInt(),
            endCol = range.end.col.toInt(),
        )
    }

    override fun readText(
        startRow: UInt,
        startCol: UInt,
        endRow: UInt,
        endCol: UInt,
    ): String? = readTextBlocking(
        startRow = startRow.toInt(),
        startCol = startCol.toInt(),
        endRow = endRow.toInt(),
        endCol = endCol.toInt(),
    )

    override fun cellMetrics(): TerminalCellMetrics {
        val size = runOnMainBlocking { surface.surfaceSize() }
        if (size == null) {
            return TerminalCellMetrics(
                cellWidthPx = 0f,
                cellHeightPx = 0f,
                cols = 0u,
                rows = 0u,
                viewportTop = 0u,
            )
        }
        return TerminalCellMetrics(
            cellWidthPx = size.cellWidthPx.toFloat(),
            cellHeightPx = size.cellHeightPx.toFloat(),
            cols = size.columns.toUInt(),
            rows = size.rows.toUInt(),
            // Selection coords are viewport-relative; scrollback gating
            // is the OSC parser's job, not ours.
            viewportTop = 0u,
        )
    }

    override fun setSelectionOverlay(range: TerminalCellRange?) {
        selectionRange.set(range)
        val callback = onSelectionRangeChanged
        runOnMain { callback?.invoke(range) }
    }

    /// Snapshot the current selection range (for the overlay view / edit
    /// menu without going through Rust).
    fun currentSelectionRange(): TerminalCellRange? = selectionRange.get()

    private fun readTextBlocking(
        startRow: Int,
        startCol: Int,
        endRow: Int,
        endCol: Int,
    ): String? = runOnMainBlocking {
        surface.readText(startRow, startCol, endRow, endCol)
    }

    private fun <T> runOnMainBlocking(block: () -> T?): T? {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return block()
        }
        val result = AtomicReference<T?>(null)
        val latch = CountDownLatch(1)
        mainHandler.post {
            try {
                result.set(block())
            } finally {
                latch.countDown()
            }
        }
        latch.await()
        return result.get()
    }

    private fun packMods(mods: TerminalKeyMods): Int {
        var bits = 0
        if (mods.shift) bits = bits or (1 shl 0)
        if (mods.ctrl) bits = bits or (1 shl 1)
        if (mods.alt) bits = bits or (1 shl 2)
        if (mods.meta) bits = bits or (1 shl 3)
        return bits
    }

    // Mirrors `LitterBridgeKey` in ghostty_jni.cpp; the JNI bridge does the
    // final translation to ghostty_input_key_e.
    private fun bridgeKey(code: TerminalKeyCode): Int = when (code) {
        is TerminalKeyCode.Enter -> 1
        is TerminalKeyCode.Tab -> 2
        is TerminalKeyCode.Backspace -> 3
        is TerminalKeyCode.Escape -> 4
        is TerminalKeyCode.Space -> 5
        is TerminalKeyCode.ArrowUp -> 6
        is TerminalKeyCode.ArrowDown -> 7
        is TerminalKeyCode.ArrowLeft -> 8
        is TerminalKeyCode.ArrowRight -> 9
        is TerminalKeyCode.PageUp -> 10
        is TerminalKeyCode.PageDown -> 11
        is TerminalKeyCode.Home -> 12
        is TerminalKeyCode.End -> 13
        is TerminalKeyCode.Delete -> 14
        is TerminalKeyCode.Insert -> 15
        else -> 0
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }
}
