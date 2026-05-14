package com.litter.android.state

import org.junit.Assert.assertEquals
import org.junit.Test

class SnapshotExtensionsTest {

    @Test
    fun `displayModelLabel uses concrete thread model first`() {
        assertEquals(
            "gpt-5.4",
            displayModelLabel(
                model = "gpt-5.4",
                infoModel = null,
                modelProvider = "anthropic",
                agentRuntimeKind = "claude",
            ),
        )
    }

    @Test
    fun `displayModelLabel falls back to provider and runtime labels`() {
        assertEquals(
            "Claude",
            displayModelLabel(
                model = null,
                infoModel = null,
                modelProvider = "anthropic",
                agentRuntimeKind = "claude",
            ),
        )
        assertEquals(
            "Opencode",
            displayModelLabel(
                model = null,
                infoModel = null,
                modelProvider = null,
                agentRuntimeKind = "opencode",
            ),
        )
    }
}
