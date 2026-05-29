package com.litter.android.auth

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.litter.android.util.LLog
import java.util.concurrent.atomic.AtomicLong

internal object ChatGPTOAuthAppReturnSignal {
    private val generation = AtomicLong(0L)

    fun signal() {
        generation.incrementAndGet()
    }

    fun snapshot(): Long = generation.get()
}

class ChatGPTOAuthRedirectActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ChatGPTOAuthAppReturnSignal.signal()
        LLog.d("ChatGPTOAuth", "redirect activity received app return")
        startActivity(
            Intent(this, ChatGPTOAuthActivity::class.java)
                .setAction(ChatGPTOAuthActivity.ACTION_BROWSER_RETURN)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        )
        finish()
    }
}
