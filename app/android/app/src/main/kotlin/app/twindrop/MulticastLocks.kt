package app.twindrop

import android.content.Context
import android.net.wifi.WifiManager

/**
 * MulticastLock is held only while mDNS discovery is running (docs/06 §2, docs/05).
 * Released on service teardown so the Wi-Fi radio is never pinned for nothing.
 */
object MulticastLocks {
    private var lock: WifiManager.MulticastLock? = null
    private var held = false

    @Synchronized
    fun acquire(context: Context): Boolean {
        if (held) return true
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return false
        val created = wifi.createMulticastLock("twindrop-discovery")
        created.setReferenceCounted(false)
        return try {
            created.acquire()
            lock = created
            held = true
            true
        } catch (_: Exception) {
            false
        }
    }

    @Synchronized
    fun release() {
        if (!held) return
        try {
            lock?.release()
        } catch (_: Exception) {
            // ignore
        }
        lock = null
        held = false
    }
}
