package com.litter.android.ui.terminal

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import uniffi.codex_mobile_client.TerminalConfig
import uniffi.codex_mobile_client.TerminalCursorStyle
import uniffi.codex_mobile_client.TerminalThemePreset

enum class TerminalThemeChoice(val id: String, val title: String) {
    LITTER_DARK("litter-dark", "Litter Dark"),
    CATPPUCCIN_FRAPPE("catppuccin-frappe", "Catppuccin Frappé"),
    CATPPUCCIN_FRAPPE_LIGHT("catppuccin-frappe-light", "Catppuccin Frappé Light"),
    SOLARIZED_DARK("solarized-dark", "Solarized Dark"),
    SOLARIZED_LIGHT("solarized-light", "Solarized Light");

    fun toPreset(): TerminalThemePreset = when (this) {
        LITTER_DARK -> TerminalThemePreset.LitterDark
        CATPPUCCIN_FRAPPE -> TerminalThemePreset.CatppuccinFrappe
        CATPPUCCIN_FRAPPE_LIGHT -> TerminalThemePreset.CatppuccinFrappeLight
        SOLARIZED_DARK -> TerminalThemePreset.Solarized(dark = true)
        SOLARIZED_LIGHT -> TerminalThemePreset.Solarized(dark = false)
    }

    companion object {
        val DEFAULT = LITTER_DARK

        fun fromId(id: String?): TerminalThemeChoice =
            entries.firstOrNull { it.id == id } ?: DEFAULT
    }
}

/**
 * Persisted terminal config (font size, theme, cursor blink). Mirrors the
 * iOS `@AppStorage` keys so the two platforms feel identical.
 */
object TerminalConfigPrefs {
    private const val PREFS = "litter_terminal_prefs"
    private const val KEY_FONT_SIZE = "fontSize"
    private const val KEY_THEME_ID = "themeId"
    private const val KEY_CURSOR_BLINK = "cursorBlink"

    private const val DEFAULT_FONT_SIZE = 13.0f
    private const val DEFAULT_CURSOR_BLINK = true

    var fontSize by mutableFloatStateOf(DEFAULT_FONT_SIZE)
        private set
    var theme by mutableStateOf(TerminalThemeChoice.DEFAULT)
        private set
    var cursorBlink by mutableStateOf(DEFAULT_CURSOR_BLINK)
        private set

    fun initialize(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        fontSize = prefs.getFloat(KEY_FONT_SIZE, DEFAULT_FONT_SIZE)
        theme = TerminalThemeChoice.fromId(prefs.getString(KEY_THEME_ID, TerminalThemeChoice.DEFAULT.id))
        cursorBlink = prefs.getBoolean(KEY_CURSOR_BLINK, DEFAULT_CURSOR_BLINK)
    }

    fun setFontSize(context: Context, value: Float) {
        val clamped = value.coerceIn(10f, 24f)
        fontSize = clamped
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putFloat(KEY_FONT_SIZE, clamped).apply()
    }

    fun setTheme(context: Context, choice: TerminalThemeChoice) {
        theme = choice
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_THEME_ID, choice.id).apply()
    }

    fun setCursorBlink(context: Context, enabled: Boolean) {
        cursorBlink = enabled
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_CURSOR_BLINK, enabled).apply()
    }

    fun currentConfig(): TerminalConfig = TerminalConfig(
        theme = theme.toPreset(),
        fontFamily = "monospace",
        fontSizePt = fontSize,
        cursorStyle = TerminalCursorStyle.BAR,
        cursorBlink = cursorBlink,
        scrollbackLines = 10_000u,
    )
}
