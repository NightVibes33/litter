package com.litter.android.ui.conversation

internal fun responseSubmissionErrorMessage(error: Throwable): String {
    val message = error.message?.trim().orEmpty()
    return if (error.isDisconnectedTransportError()) {
        "Connection lost. Try again after Litter reconnects."
    } else {
        message.ifEmpty { "Failed to submit response." }
    }
}

internal fun Throwable.isDisconnectedTransportError(): Boolean {
    val message = this.message?.lowercase().orEmpty()
    return "disconnected" in message ||
        ("transport error" in message && "not connected" in message)
}
