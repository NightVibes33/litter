package com.litter.android.ui.voice

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.litter.android.state.VoiceRuntimeController
import com.litter.android.state.resolvedPreview
import com.litter.android.ui.LocalAppModel
import com.litter.android.ui.LitterTheme
import kotlinx.coroutines.launch
import uniffi.codex_mobile_client.AppVoiceSessionPhase
import uniffi.codex_mobile_client.ThreadKey

/**
 * Companion transcript view during active voice session.
 * Shows audio level indicators and conversation content.
 */
@Composable
fun VoiceCallView(
    threadKey: ThreadKey,
    onHangUp: () -> Unit,
) {
    val appModel = LocalAppModel.current
    val voiceController = remember { VoiceRuntimeController.shared }
    val session by voiceController.activeVoiceSession.collectAsState()
    val snapshot by appModel.snapshot.collectAsState()
    val scope = rememberCoroutineScope()
    val voiceSession = snapshot?.voiceSession

    val thread = remember(snapshot, threadKey) {
        snapshot?.threads?.find { it.key == threadKey }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // Top bar with audio levels
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .background(LitterTheme.surface)
                .padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = thread?.resolvedPreview ?: "Voice Session",
                    color = LitterTheme.textPrimary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    text = when (voiceSession?.phase) {
                        AppVoiceSessionPhase.CONNECTING -> "CONNECTING"
                        AppVoiceSessionPhase.LISTENING -> "LISTENING"
                        AppVoiceSessionPhase.SPEAKING -> "SPEAKING"
                        AppVoiceSessionPhase.THINKING -> "THINKING"
                        AppVoiceSessionPhase.HANDOFF -> "HANDOFF"
                        AppVoiceSessionPhase.ERROR -> "ERROR"
                        null -> ""
                    },
                    color = LitterTheme.accent,
                    fontSize = 11.sp,
                )
            }

            // Input level
            LinearProgressIndicator(
                progress = { session?.inputLevel ?: 0f },
                modifier = Modifier
                    .width(40.dp)
                    .height(4.dp)
                    .clip(RoundedCornerShape(2.dp)),
                color = LitterTheme.accent,
                trackColor = LitterTheme.codeBackground,
            )
            Spacer(Modifier.width(8.dp))

            // Output level
            LinearProgressIndicator(
                progress = { session?.outputLevel ?: 0f },
                modifier = Modifier
                    .width(40.dp)
                    .height(4.dp)
                    .clip(RoundedCornerShape(2.dp)),
                color = Color(0xFF4A9EFF),
                trackColor = LitterTheme.codeBackground,
            )
            Spacer(Modifier.width(8.dp))

            IconButton(onClick = { /* TODO: toggle speaker route */ }, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Default.VolumeUp, "Speaker", tint = LitterTheme.textSecondary)
            }
        }

        // Conversation transcript (reuse ConversationScreen content)
        Box(modifier = Modifier.weight(1f)) {
            // TODO: Render conversation items for threadKey
            Text(
                text = "Transcript",
                color = LitterTheme.textMuted,
                modifier = Modifier.align(Alignment.Center),
            )
        }

        // Bottom bar
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .background(LitterTheme.surface)
                .padding(16.dp),
        ) {
            Spacer(Modifier.weight(1f))
            IconButton(
                onClick = {
                    scope.launch {
                        voiceController.stopActiveVoiceSession(appModel)
                        onHangUp()
                    }
                },
                modifier = Modifier
                    .size(48.dp)
                    .background(LitterTheme.danger, CircleShape),
            ) {
                Icon(Icons.Default.CallEnd, "Hang up", tint = Color.White)
            }
            Spacer(Modifier.weight(1f))
        }
    }
}
