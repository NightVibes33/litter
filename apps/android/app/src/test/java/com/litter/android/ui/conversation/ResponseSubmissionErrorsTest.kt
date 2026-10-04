package com.litter.android.ui.conversation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ResponseSubmissionErrorsTest {
    @Test
    fun disconnectedTransportErrorsUseRetryMessage() {
        val error = RuntimeException("v1=transport error: disconnected")

        assertTrue(error.isDisconnectedTransportError())
        assertEquals(
            "Connection lost. Try again after Litter reconnects.",
            responseSubmissionErrorMessage(error),
        )
    }

    @Test
    fun notConnectedTransportErrorsUseRetryMessage() {
        val error = RuntimeException("transport error: not connected")

        assertTrue(error.isDisconnectedTransportError())
        assertEquals(
            "Connection lost. Try again after Litter reconnects.",
            responseSubmissionErrorMessage(error),
        )
    }

    @Test
    fun nonTransportErrorsKeepOriginalMessage() {
        val error = IllegalStateException("approval no longer pending")

        assertFalse(error.isDisconnectedTransportError())
        assertEquals("approval no longer pending", responseSubmissionErrorMessage(error))
    }
}
