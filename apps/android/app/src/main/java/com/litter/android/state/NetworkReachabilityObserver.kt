package com.litter.android.state

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import com.litter.android.util.LLog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Observes Android network reachability and forwards change events to the
 * shared Rust client so iroh-backed (alleycat) sessions can re-evaluate
 * paths immediately on Wi-Fi ↔ cellular handoff, VPN toggle, etc.
 *
 * Without this, iroh would only notice a fundamental network change via
 * the QUIC idle timeout (~30s); we'd rather hint it the moment the OS
 * does. Bind once per app at startup (after [AppModel] is constructed),
 * call [start] to register, [stop] to unregister.
 */
class NetworkReachabilityObserver(
    context: Context,
    private val appModel: AppModel,
) {
    private val connectivity =
        context.applicationContext.getSystemService(ConnectivityManager::class.java)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var debounceJob: Job? = null
    @Volatile private var lastSatisfied: Boolean? = null

    /**
     * What we actually care about for "did the network meaningfully
     * change?" Two paths with the same fingerprint produce no hint —
     * `ConnectivityManager.NetworkCallback` fires for many incidental
     * capability flips we don't want to forward to iroh.
     */
    private data class PathFingerprint(
        val available: Boolean,
        val validated: Boolean,
        val transports: List<Int>,
        val isMetered: Boolean,
    )

    private fun fingerprintFor(capabilities: NetworkCapabilities?, available: Boolean): PathFingerprint {
        if (capabilities == null) {
            return PathFingerprint(
                available = available,
                validated = false,
                transports = emptyList(),
                isMetered = false,
            )
        }
        val transports =
            listOf(
                NetworkCapabilities.TRANSPORT_WIFI,
                NetworkCapabilities.TRANSPORT_CELLULAR,
                NetworkCapabilities.TRANSPORT_ETHERNET,
                NetworkCapabilities.TRANSPORT_VPN,
            ).filter(capabilities::hasTransport)
        return PathFingerprint(
            available = available,
            validated = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
            transports = transports,
            isMetered = !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED),
        )
    }

    @Volatile private var lastFingerprint: PathFingerprint? = null

    private val callback =
        object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val caps = connectivity?.getNetworkCapabilities(network)
                schedule(fingerprintFor(caps, available = true))
            }

            override fun onLost(network: Network) {
                schedule(fingerprintFor(null, available = false))
            }

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities,
            ) {
                schedule(fingerprintFor(capabilities, available = true))
            }
        }

    fun start() {
        val cm = connectivity ?: return
        try {
            cm.registerDefaultNetworkCallback(callback)
        } catch (e: SecurityException) {
            LLog.w("NetworkReachability", "registerDefaultNetworkCallback failed: ${e.message}")
        }
    }

    fun stop() {
        val cm = connectivity ?: return
        try {
            cm.unregisterNetworkCallback(callback)
        } catch (e: IllegalArgumentException) {
            // Already unregistered.
        }
        debounceJob?.cancel()
        debounceJob = null
    }

    private fun schedule(fingerprint: PathFingerprint) {
        // Drop the first observation: it reflects current state at
        // registration, not a transition. After that, only meaningful
        // fingerprint changes get forwarded.
        val previous = lastFingerprint
        if (previous == null) {
            lastFingerprint = fingerprint
            lastSatisfied = fingerprint.validated
            return
        }
        if (previous == fingerprint) return

        val regainedAfterLoss = fingerprint.validated && lastSatisfied == false
        lastFingerprint = fingerprint
        lastSatisfied = fingerprint.validated

        debounceJob?.cancel()
        debounceJob =
            scope.launch {
                delay(DEBOUNCE_MS)
                LLog.i(
                    "NetworkReachability",
                    "reachability change available=${fingerprint.available} validated=${fingerprint.validated} " +
                        "transports=${fingerprint.transports} regainedAfterLoss=$regainedAfterLoss",
                )
                appModel.reconnectController.notifyNetworkChange()
                if (regainedAfterLoss) {
                    appModel.reconnectController.onNetworkReachable()
                }
            }
    }

    private companion object {
        // Bursty callbacks during interface flaps coalesce into a single
        // hint to Rust. 250ms is short enough to feel instant, long
        // enough to avoid spamming.
        const val DEBOUNCE_MS = 250L
    }
}
