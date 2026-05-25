package com.litter.android.state

import android.content.Context
import uniffi.codex_mobile_client.TerminalSshTrustBackend

/// Persistent host-key fingerprint pinning backed by EncryptedSharedPreferences.
/// Implements the Rust [`TerminalSshTrustBackend`] callback interface so the
/// shared terminal SSH backend can consult and update pins on every connect.
class SshTrustStore(context: Context) : TerminalSshTrustBackend {
    private val prefs = openEncryptedPrefsOrReset(context, PREFS_NAME)

    override fun read(host: String, port: UShort): String? {
        return prefs.getString(key(host, port), null)
    }

    override fun write(host: String, port: UShort, fingerprint: String) {
        prefs.edit().putString(key(host, port), fingerprint).apply()
    }

    override fun remove(host: String, port: UShort) {
        prefs.edit().remove(key(host, port)).apply()
    }

    private fun key(host: String, port: UShort): String = "${host.lowercase()}:$port"

    companion object {
        private const val PREFS_NAME = "litter_ssh_trust"
    }
}
