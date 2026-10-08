package com.litter.android.ui.tv

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.litter.android.ui.LitterTheme

@Composable
fun Modifier.tvFocusOutline(): Modifier {
    val context = LocalContext.current
    val television = (context.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager)?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    var focused by remember { mutableStateOf(false) }
    return if (television) this.onFocusChanged { focused = it.hasFocus }
        .border(2.dp, if (focused) LitterTheme.accent else Color.Transparent, RoundedCornerShape(10.dp)) else this
}
