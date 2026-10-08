package com.litter.android.ui.tv

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.litter.android.state.AppIconController
import com.litter.android.ui.LitterTheme

@Composable
fun TvIconSwitcher(onBack: () -> Unit) {
    val context = LocalContext.current
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { AppIconController.initialize(context) }
    Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            TvButton("Back", onBack)
            Text("Icon Switcher", fontSize = 28.sp, color = LitterTheme.textPrimary)
        }
        Text("Choose your Alley Cåt icon. TV launchers may take a moment to refresh the tile.", color = LitterTheme.textSecondary)
        error?.let { Text(it, color = LitterTheme.danger) }
        LazyVerticalGrid(columns = GridCells.Adaptive(220.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(AppIconController.options, key = { it.id }) { option ->
                Column {
                    Image(painterResource(option.drawable), null, Modifier.size(100.dp))
                    TvButton((if (AppIconController.selected == option) "✓ " else "") + option.title, {
                        error = null
                        try { AppIconController.apply(context, option) }
                        catch (_: Exception) { error = "Could not change the launcher icon. Your previous icon was retained." }
                    }, Modifier.fillMaxWidth())
                }
            }
        }
    }
}
