package com.litter.android.ui.tv

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import com.sigkitten.litter.android.R
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.litter.android.ui.LitterTheme
import com.litter.android.ui.home.HomeDashboardSupport
import uniffi.codex_mobile_client.AppSnapshotRecord
import uniffi.codex_mobile_client.ThreadKey

/** Remote-first home; session state and navigation remain shared with mobile. */
@Composable
fun TvHomeScreen(
    snapshot: AppSnapshotRecord?,
    onOpenConversation: (ThreadKey) -> Unit,
    onShowDiscovery: () -> Unit,
    onShowSettings: () -> Unit,
    onShowApps: () -> Unit,
    onNewChat: () -> Unit = {},
    isStartingChat: Boolean = false,
    chatError: String? = null,
) {
    val initialFocus = remember { FocusRequester() }
    val sessions = remember(snapshot?.sessionSummaries, snapshot?.servers, snapshot?.threads) {
        snapshot?.let { HomeDashboardSupport.recentSessions(it, Int.MAX_VALUE) }.orEmpty()
    }
    LaunchedEffect(Unit) { initialFocus.requestFocus() }

    Column(
        Modifier.fillMaxSize().background(LitterTheme.background).padding(horizontal = 48.dp, vertical = 27.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            Image(painterResource(R.drawable.alley_cat_app_icon), contentDescription = null,
                modifier = Modifier.size(80.dp).clip(RoundedCornerShape(20.dp)))
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Alley Cåt", fontSize = 36.sp, fontWeight = FontWeight.Bold, color = LitterTheme.textPrimary)
                Text("Your coding workspace", fontSize = 20.sp, color = LitterTheme.textSecondary)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            TvButton(if (isStartingChat) "Starting chat..." else "New Chat",
                { if (!isStartingChat) onNewChat() }, Modifier.focusRequester(initialFocus))
            TvButton("Add server", onShowDiscovery)
            TvButton("Settings", onShowSettings)
            TvButton("Apps", onShowApps)
        }
        chatError?.let { Text(it, color = LitterTheme.textSecondary, fontSize = 18.sp) }
        Text("Recent conversations", fontSize = 24.sp, color = LitterTheme.textPrimary)
        if (sessions.isEmpty()) {
            Text(
                "No recent conversations yet. Select New Chat to start with your signed-in account, or Add server to connect another workspace.",
                color = LitterTheme.textSecondary,
                fontSize = 20.sp,
            )
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(sessions, key = { "${it.key.serverId.length}:${it.key.serverId}${it.key.threadId}" }) { session ->
                TvButton(
                    HomeDashboardSupport.sessionTitle(session),
                    { onOpenConversation(session.key) },
                    Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun TvButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    var focused by remember { mutableStateOf(false) }
    Button(
        onClick = onClick,
        modifier = modifier.onFocusChanged { focused = it.isFocused },
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(3.dp, if (focused) LitterTheme.accent else LitterTheme.border),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (focused) LitterTheme.accent.copy(alpha = 0.16f) else LitterTheme.surface,
            contentColor = LitterTheme.textPrimary,
        ),
        contentPadding = PaddingValues(horizontal = 24.dp, vertical = 16.dp),
    ) {
        Text(label, fontSize = 20.sp)
    }
}
