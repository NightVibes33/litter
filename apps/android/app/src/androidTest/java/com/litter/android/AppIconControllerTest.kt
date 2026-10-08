package com.litter.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.litter.android.state.AppIconController
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppIconControllerTest {
    @Test fun allThirteenLauncherIconsCanBeAppliedAndRestored() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        AppIconController.initialize(context)
        val previous = AppIconController.selected
        try {
            assertEquals(13, AppIconController.options.size)
            for (option in AppIconController.options) {
                AppIconController.apply(context, option)
                AppIconController.initialize(context)
                assertEquals(option, AppIconController.selected)
            }
        } finally { AppIconController.apply(context, previous) }
    }
}
