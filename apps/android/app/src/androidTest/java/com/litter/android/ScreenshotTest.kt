package com.litter.android

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import tools.fastlane.screengrab.Screengrab
import tools.fastlane.screengrab.UiAutomatorScreenshotStrategy
import tools.fastlane.screengrab.locale.LocaleTestRule

@RunWith(AndroidJUnit4::class)
class ScreenshotTest {

    @get:Rule
    val localeTestRule = LocaleTestRule()

    @get:Rule
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun captureScreenshots() {
        Screengrab.setDefaultScreenshotStrategy(UiAutomatorScreenshotStrategy())

        // Wait for splash screen to dismiss and app to settle
        composeTestRule.waitForIdle()
        Thread.sleep(4000)

        // 01 - Home dashboard
        Screengrab.screenshot("01_Home")

        // 02 - Settings sheet
        composeTestRule.onNodeWithContentDescription("Settings").performClick()
        composeTestRule.waitForIdle()
        Thread.sleep(800)
        Screengrab.screenshot("02_Settings")

        // 03 - Theme / Appearance
        try {
            composeTestRule.onNodeWithText("Appearance").performClick()
            composeTestRule.waitForIdle()
            Thread.sleep(800)
            Screengrab.screenshot("03_Themes")
        } catch (_: Exception) {}

        // Dismiss settings
        composeTestRule.activityRule.scenario.onActivity {
            it.onBackPressedDispatcher.onBackPressed()
        }
        Thread.sleep(500)
        composeTestRule.activityRule.scenario.onActivity {
            it.onBackPressedDispatcher.onBackPressed()
        }
        Thread.sleep(500)
    }
}
