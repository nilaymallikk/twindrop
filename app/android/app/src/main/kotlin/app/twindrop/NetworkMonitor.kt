package app.twindrop

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper

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

    /**
     * The connectivity callbacks arrive on a background thread ("ConnectivityThread"),
     * but a platform-channel call must be made on the main thread: Flutter throws
     * "Methods marked with @UiThread must be executed on the main thread" and the
     * process dies. Every callback is therefore hopped onto the main looper here.
     */
    private val mainHandler = Handler(Looper.getMainLooper())

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

    /**
     * Reports the current network state to [onChanged] on the main thread.
     */
    fun emit() {
        val state = current()
        mainHandler.post { onChanged(state) }
    }

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
