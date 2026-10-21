package app.twindrop

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities

/**
 * Network changes are pushed to Dart so the connection manager reconnects immediately
 * (docs/06 §2) instead of waiting for the next backoff tick.
 */
class NetworkMonitor(
    context: Context,
    private val onChanged: (Map<String, Any?>) -> Unit,
) {
    private val connectivity =
        context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = emit()

        override fun onLost(network: Network) = emit()

        override fun onCapabilitiesChanged(
            network: Network,
            capabilities: NetworkCapabilities,
        ) = emit()
    }

    @Volatile
    private var registered = false

    fun start() {
        if (registered) return
        try {
            connectivity.registerDefaultNetworkCallback(callback)
            registered = true
        } catch (_: Exception) {
            registered = false
        }
    }

    fun stop() {
        if (!registered) return
        try {
            connectivity.unregisterNetworkCallback(callback)
        } catch (_: Exception) {
            // ignore
        }
        registered = false
    }

    fun emit() = onChanged(current())

    fun current(): Map<String, Any?> {
        val network = connectivity.activeNetwork
        val caps = network?.let { connectivity.getNetworkCapabilities(it) }
        val wifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        val cellular = caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true
        val ethernet = caps?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true
        val vpn = caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        val validated = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
        return mapOf(
            "online" to (caps != null && validated),
            "wifi" to wifi,
            "cellular" to cellular,
            "ethernet" to ethernet,
            "vpn" to vpn,
        )
    }
}
