package com.litter.android.state

import android.content.Context

/**
 * Convert filesystem paths to short, user-facing strings.
 *
 * For **local** codex paths, rewrites the `HomeAnchor.path(context)` and
 * `$TMPDIR` to `~` and `/tmp` so the UI shows `~/projects/foo` and
 * `/tmp/x.txt` instead of the raw `/data/user/0/com.sigkitten.litter/files/...`
 * absolute paths.
 *
 * For **remote** paths, shortens paths under a resolved remote home directory
 * when the caller provides one.
 */
object PathDisplay {
    /**
     * Callers pass [isLocal] `= true` only when [raw] is a path on the
     * in-process Android codex. Remote-server paths can be abbreviated when
     * [remoteHome] is known.
     */
    fun display(
        raw: String,
        isLocal: Boolean,
        context: Context,
        remoteHome: String? = null,
    ): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return if (isLocal) "~" else trimmed
        if (!isLocal) return remoteDisplay(trimmed, remoteHome)
        val home = HomeAnchor.path(context)
        if (trimmed == home) return "~"
        if (trimmed.startsWith("$home/")) return "~/" + trimmed.substring(home.length + 1)
        val tmp = realTmp()
        if (tmp.isNotEmpty()) {
            if (trimmed == tmp) return "/tmp"
            if (trimmed.startsWith("$tmp/")) return "/tmp/" + trimmed.substring(tmp.length + 1)
        }
        return trimmed
    }

    /** Inverse of [display] for user-entered display strings on the selected server. */
    fun expand(
        display: String,
        isLocal: Boolean,
        context: Context,
        remoteHome: String? = null,
    ): String {
        val trimmed = display.trim()
        if (!isLocal) return expandRemoteDisplay(trimmed, remoteHome)
        if (trimmed == "~") return HomeAnchor.path(context)
        if (trimmed.startsWith("~/")) return HomeAnchor.path(context) + "/" + trimmed.substring(2)
        val tmp = realTmp()
        if (tmp.isNotEmpty()) {
            if (trimmed == "/tmp") return tmp
            if (trimmed.startsWith("/tmp/")) return "$tmp/" + trimmed.substring(5)
        }
        return trimmed
    }

    private fun realTmp(): String {
        // Set by `Java_com_litter_android_core_bridge_UniffiInit_nativeBridgeInit`
        // at JNI boot. Strip trailing slash so comparisons are uniform.
        val raw = System.getenv("TMPDIR") ?: return ""
        return if (raw.endsWith("/")) raw.dropLast(1) else raw
    }

    private fun remoteDisplay(raw: String, remoteHome: String?): String {
        val home = remoteHome?.trim().orEmpty()
        if (home.isEmpty()) return raw
        val windows = isWindowsPath(home)
        val normalizedRaw = if (windows) raw.replace('/', '\\') else raw
        val normalizedHome = if (windows) home.replace('/', '\\').trimEnd('\\') else home.trimEnd('/')
        if (normalizedHome.isEmpty()) return raw
        if (windows) {
            if (normalizedRaw.equals(normalizedHome, ignoreCase = true)) return "~"
            val prefix = "$normalizedHome\\"
            if (normalizedRaw.startsWith(prefix, ignoreCase = true)) {
                return "~\\" + normalizedRaw.substring(prefix.length)
            }
            return raw
        }
        if (normalizedRaw == normalizedHome) return "~"
        val prefix = "$normalizedHome/"
        if (normalizedRaw.startsWith(prefix)) return "~/" + normalizedRaw.substring(prefix.length)
        return raw
    }

    private fun expandRemoteDisplay(display: String, remoteHome: String?): String {
        val home = remoteHome?.trim().orEmpty()
        if (home.isEmpty()) return display
        val windows = isWindowsPath(home)
        val normalizedHome = if (windows) home.replace('/', '\\').trimEnd('\\') else home.trimEnd('/')
        if (normalizedHome.isEmpty()) return display
        if (windows) {
            if (display == "~") return normalizedHome
            if (display.startsWith("~\\") || display.startsWith("~/")) {
                return normalizedHome + "\\" + display.substring(2).replace('/', '\\')
            }
            return display
        }
        if (display == "~") return normalizedHome
        if (display.startsWith("~/")) return "$normalizedHome/${display.substring(2)}"
        return display
    }

    private fun isWindowsPath(path: String): Boolean =
        path.length >= 2 && path[0].isLetter() && path[1] == ':'
}
