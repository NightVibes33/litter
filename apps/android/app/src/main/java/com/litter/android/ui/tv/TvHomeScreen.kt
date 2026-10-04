package com.litter.android.ui.tv

import androidx.compose.foundation.BorderStroke
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
) {
    val initialFocus = remember { FocusRequester() }
    val sessions = remember(snapshot?.sessionSummaries, snapshot?.servers, snapshot?.threads) {
        snapshot?.let { HomeDashboardSupport.recentSessions(it, Int.MAX_VALUE) }.orEmpty()
    }
    LaunchedEffect(Unit) { initialFocus.requestFocus() }

    Column(
        Modifier.fillMaxSize().padding(horizontal = 48.dp, vertical = 27.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Text("Alley Cãt", fontSize = 32.sp, color = LitterTheme.textPrimary)
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            TvButton("Add server", onShowDiscovery, Modifier.focusRequester(initialFocus))
            TvButton("Settings", onShowSettings)
            TvButton("Apps", onShowApps)
        }
        Text("Recent conversations", fontSize = 24.sp, color = LitterTheme.textPrimary)
        if (sessions.isEmpty()) {
            Text(
                "Add a server to start. Use the remote arrows to move and Select to open.",
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
        border = BorderStroke(3.dp, if (focused) LitterTheme.accent else LitterTheme.border),
        colors = ButtonDefaults.buttonColors(
            containerColor = LitterTheme.surface,
            contentColor = LitterTheme.textPrimary,
        ),
        contentPadding = PaddingValues(horizontal = 24.dp, vertical = 16.dp),
    ) {
        Text(label, fontSize = 20.sp)
    }
}
