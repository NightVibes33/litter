package com.litter.android.state

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.sigkitten.litter.android.R

data class AppIconOption(val id: String, val title: String, val drawable: Int)

/** Launcher state is authoritative; never disable the actual activity. */
object AppIconController {
    val options = listOf(
        AppIconOption("current", "Alley Cåt", R.drawable.app_icon_current),
        AppIconOption("original", "Original Icon", R.drawable.app_icon_original),
        AppIconOption("shinobi", "Shinobi Cats", R.drawable.app_icon_shinobi),
        AppIconOption("electric_pulse", "Electric Pulse", R.drawable.app_icon_electric_pulse),
        AppIconOption("ocean_connect", "Ocean Connect", R.drawable.app_icon_ocean_connect),
        AppIconOption("devine_purple", "Devine Purple", R.drawable.app_icon_devine_purple),
        AppIconOption("green_terminal", "Green Terminal", R.drawable.app_icon_green_terminal),
        AppIconOption("cosmic_forum", "Cosmic Forum", R.drawable.app_icon_cosmic_forum),
        AppIconOption("crystal_frost", "Crystal Frost", R.drawable.app_icon_crystal_frost),
        AppIconOption("cyber_district", "Cyber District", R.drawable.app_icon_cyber_district),
        AppIconOption("midnight_amoled", "Midnight AMOLED", R.drawable.app_icon_midnight_amoled),
        AppIconOption("rgb_arena", "RGB Arena", R.drawable.app_icon_rgb_arena),
        AppIconOption("neural_core", "Neural Core", R.drawable.app_icon_neural_core)
    )
    var selected by mutableStateOf(options.first())
        private set

    private fun component(context: Context, option: AppIconOption) =
        ComponentName(context.packageName, "com.litter.android.launcher.Icon_${option.id}")

    private fun enabled(context: Context, option: AppIconOption): Boolean =
        when (context.packageManager.getComponentEnabledSetting(component(context, option))) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> option.id == "current"
            else -> false
        }

    fun initialize(context: Context) {
        selected = options.firstOrNull { enabled(context, it) } ?: options.first()
    }

    fun apply(context: Context, option: AppIconOption) {
        require(option in options)
        val pm = context.packageManager
        val before = options.associateWith { pm.getComponentEnabledSetting(component(context, it)) }
        try {
            // Enable first so the launcher never loses its only entry point.
            pm.setComponentEnabledSetting(component(context, option),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
            options.filter { it != option }.forEach {
                pm.setComponentEnabledSetting(component(context, it),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            }
            check(enabled(context, option) && options.count { enabled(context, it) } == 1)
            selected = option
        } catch (error: Exception) {
            before.forEach { (entry, state) ->
                runCatching { pm.setComponentEnabledSetting(component(context, entry), state, PackageManager.DONT_KILL_APP) }
            }
            initialize(context)
            throw error
        }
    }
}
