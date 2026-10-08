package com.litter.android

import androidx.compose.ui.input.key.Key
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.pressKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.litter.android.ui.LitterAppTheme
import com.litter.android.ui.tv.TvHomeScreen
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TvHomeScreenTest {
    @get:Rule
    val compose = createComposeRule()

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun remoteCanMoveFromInitialActionAndActivateSettings() {
        var settingsOpened = 0
        compose.setContent {
            LitterAppTheme {
                TvHomeScreen(
                    snapshot = null,
                    onOpenConversation = {},
                    onShowDiscovery = {},
                    onShowSettings = { settingsOpened++ },
                    onShowApps = {},
                )
            }
        }
        compose.onNodeWithText("New Chat").assertIsFocused()
            .performKeyInput { pressKey(Key.DirectionRight) }
        compose.onNodeWithText("Add server").assertIsFocused()
            .performKeyInput { pressKey(Key.DirectionRight) }
        compose.onNodeWithText("Settings").assertIsFocused()
            .performKeyInput { pressKey(Key.DirectionCenter) }
        compose.runOnIdle { assertEquals(1, settingsOpened) }
    }
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun remoteCanStartFirstChatWithoutRecentSessions() {
        var chatsStarted = 0
        compose.setContent {
            LitterAppTheme {
                TvHomeScreen(
                    snapshot = null,
                    onOpenConversation = {},
                    onShowDiscovery = {},
                    onShowSettings = {},
                    onShowApps = {},
                    onNewChat = { chatsStarted++ },
                )
            }
        }
        compose.onNodeWithText("New Chat").assertIsFocused()
            .performKeyInput { pressKey(Key.DirectionCenter) }
        compose.runOnIdle { assertEquals(1, chatsStarted) }
    }

}
