package com.litter.android.core.bridge

import android.view.Surface

data class GhosttyRendererStatus(
    val libraryLoaded: Boolean,
    val canCreateAndroidSurface: Boolean,
    val version: String?,
    val reason: String?,
)

fun interface GhosttyInputCallback {
    fun onInput(bytes: ByteArray)
}

fun interface GhosttyWakeupListener {
    fun onWakeup()
}

/// Snapshot of the Ghostty surface grid + cell metrics. Pixel sizes are
/// already multiplied by the content scale; cell sizes are floored to
/// whole pixels.
data class SurfaceSize(
    val columns: Int,
    val rows: Int,
    val widthPx: Int,
    val heightPx: Int,
    val cellWidthPx: Int,
    val cellHeightPx: Int,
)

object GhosttyRendererBridge {
    private const val rendererBlockedReason =
        "Ghostty Android GLES/EGL embedded surface is unavailable"

    private val loadResult: Result<Unit> by lazy {
        runCatching {
            System.loadLibrary("EGL")
            System.loadLibrary("GLESv3")
            System.loadLibrary("ghostty")
            System.loadLibrary("litter_ghostty_jni")
        }
    }

    fun status(): GhosttyRendererStatus {
        loadResult.exceptionOrNull()?.let { error ->
            return GhosttyRendererStatus(
                libraryLoaded = false,
                canCreateAndroidSurface = false,
                version = null,
                reason = error.message ?: "Unable to load Ghostty renderer library",
            )
        }

        val canCreateSurface = nativeCanCreateAndroidSurface()
        return GhosttyRendererStatus(
            libraryLoaded = true,
            canCreateAndroidSurface = canCreateSurface,
            version = nativeGhosttyVersion().takeIf { it.isNotBlank() },
            reason = if (canCreateSurface) null else rendererBlockedReason,
        )
    }

    fun createSurface(
        surface: Surface,
        width: Int,
        height: Int,
        scale: Float,
        fontSize: Float,
    ): GhosttyRendererSurface? {
        if (!status().canCreateAndroidSurface) return null
        val handle = nativeCreateAndroidSurface(
            surface,
            width.coerceAtLeast(1),
            height.coerceAtLeast(1),
            scale,
            fontSize,
        )
        return if (handle == 0L) null else GhosttyRendererSurface(handle)
    }

    private external fun nativeGhosttyVersion(): String

    private external fun nativeCanCreateAndroidSurface(): Boolean

    private external fun nativeCreateAndroidSurface(
        surface: Surface,
        width: Int,
        height: Int,
        scale: Float,
        fontSize: Float,
    ): Long

    private external fun nativeDestroyAndroidSurface(handle: Long)

    private external fun nativeResizeAndroidSurface(
        handle: Long,
        width: Int,
        height: Int,
        scale: Float,
    )

    private external fun nativeDrawAndroidSurface(handle: Long)

    private external fun nativeTickAndroidSurface(handle: Long): Boolean

    private external fun nativeWriteAndroidSurface(handle: Long, data: ByteArray)

    private external fun nativeSetInputCallback(handle: Long, callback: GhosttyInputCallback?)

    private external fun nativeSetWakeupListener(handle: Long, listener: GhosttyWakeupListener?)

    private external fun nativeSetOcclusion(handle: Long, occluded: Boolean)

    private external fun nativeSetFocus(handle: Long, focused: Boolean)

    private external fun nativeApplyConfig(handle: Long, path: String): Boolean

    private external fun nativeSurfaceSize(handle: Long): IntArray

    private external fun nativeReadText(
        handle: Long,
        startRow: Int,
        startCol: Int,
        endRow: Int,
        endCol: Int,
    ): String?

    private external fun nativeMouseMove(handle: Long, x: Double, y: Double, mods: Int)

    private external fun nativeMouseButton(
        handle: Long,
        pressed: Boolean,
        button: Int,
        mods: Int,
    ): Boolean

    private external fun nativeMouseCaptured(handle: Long): Boolean

    private external fun nativeMouseScroll(
        handle: Long,
        x: Double,
        y: Double,
        precise: Boolean,
        mods: Int,
    )

    private external fun nativeSendKey(
        handle: Long,
        action: Int,
        key: Int,
        mods: Int,
        text: String?,
        composing: Boolean,
    ): Boolean

    private external fun nativeSendText(handle: Long, text: String)

    private external fun nativeSendPreedit(handle: Long, text: String?)

    private external fun nativeKeyboardChanged(handle: Long)

    class GhosttyRendererSurface internal constructor(
        private var handle: Long,
    ) : AutoCloseable {
        fun resize(width: Int, height: Int, scale: Float) {
            val active = handle
            if (active == 0L) return
            nativeResizeAndroidSurface(
                active,
                width.coerceAtLeast(1),
                height.coerceAtLeast(1),
                scale,
            )
        }

        fun draw() {
            val active = handle
            if (active == 0L) return
            nativeDrawAndroidSurface(active)
        }

        fun tick(): Boolean {
            val active = handle
            if (active == 0L) return false
            return nativeTickAndroidSurface(active)
        }

        fun write(data: ByteArray) {
            val active = handle
            if (active == 0L || data.isEmpty()) return
            nativeWriteAndroidSurface(active, data)
        }

        fun setInputCallback(callback: GhosttyInputCallback?) {
            val active = handle
            if (active == 0L) return
            nativeSetInputCallback(active, callback)
        }

        fun setWakeupListener(listener: GhosttyWakeupListener?) {
            val active = handle
            if (active == 0L) return
            nativeSetWakeupListener(active, listener)
        }

        fun setOcclusion(occluded: Boolean) {
            val active = handle
            if (active == 0L) return
            nativeSetOcclusion(active, occluded)
        }

        fun setFocus(focused: Boolean) {
            val active = handle
            if (active == 0L) return
            nativeSetFocus(active, focused)
        }

        fun applyConfig(path: String): Boolean {
            val active = handle
            if (active == 0L) return false
            return nativeApplyConfig(active, path)
        }

        /// Live surface metrics. Returns `null` if the surface isn't ready
        /// or Ghostty reports zero-sized cells (e.g. before the first
        /// layout pass).
        fun surfaceSize(): SurfaceSize? {
            val active = handle
            if (active == 0L) return null
            val raw = nativeSurfaceSize(active)
            if (raw.size != 6) return null
            val cellW = raw[4]
            val cellH = raw[5]
            if (cellW <= 0 || cellH <= 0) return null
            return SurfaceSize(
                columns = raw[0],
                rows = raw[1],
                widthPx = raw[2],
                heightPx = raw[3],
                cellWidthPx = cellW,
                cellHeightPx = cellH,
            )
        }

        /// Read text from a viewport-relative cell range (inclusive on
        /// both endpoints, same coordinate space the selection overlay
        /// uses). Returns `null` if the range is empty or the surface
        /// isn't ready.
        fun readText(
            startRow: Int,
            startCol: Int,
            endRow: Int,
            endCol: Int,
        ): String? {
            val active = handle
            if (active == 0L) return null
            return nativeReadText(active, startRow, startCol, endRow, endCol)
        }

        fun mouseMove(x: Double, y: Double, mods: Int = 0) {
            val active = handle
            if (active == 0L) return
            nativeMouseMove(active, x, y, mods)
        }

        fun mouseButton(pressed: Boolean, button: Int, mods: Int = 0): Boolean {
            val active = handle
            if (active == 0L) return false
            return nativeMouseButton(active, pressed, button, mods)
        }

        fun mouseCaptured(): Boolean {
            val active = handle
            if (active == 0L) return false
            return nativeMouseCaptured(active)
        }

        fun mouseScroll(x: Double, y: Double, precise: Boolean, mods: Int = 0) {
            val active = handle
            if (active == 0L) return
            nativeMouseScroll(active, x, y, precise, mods)
        }

        fun sendKey(
            action: Int,
            key: Int,
            mods: Int,
            text: String?,
            composing: Boolean,
        ): Boolean {
            val active = handle
            if (active == 0L) return false
            return nativeSendKey(active, action, key, mods, text, composing)
        }

        fun sendText(text: String) {
            val active = handle
            if (active == 0L || text.isEmpty()) return
            nativeSendText(active, text)
        }

        fun sendPreedit(text: String?) {
            val active = handle
            if (active == 0L) return
            nativeSendPreedit(active, text)
        }

        fun keyboardChanged() {
            val active = handle
            if (active == 0L) return
            nativeKeyboardChanged(active)
        }

        override fun close() {
            val active = handle
            if (active == 0L) return
            handle = 0L
            nativeSetInputCallback(active, null)
            nativeSetWakeupListener(active, null)
            nativeDestroyAndroidSurface(active)
        }
    }
}
