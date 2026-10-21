package app.twindrop

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restarts the keep-alive service after a reboot or an app update (docs/06 §2), but only
 * when the user enabled it and a desktop is still paired. Unpaired/disabled is a no-op:
 * the service must never start silently without the onboarding consent.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
                if (Prefs.isKeepAliveEnabled(context) && Prefs.isPaired(context)) {
                    KeepAliveService.start(context)
                }
            }
        }
    }
}
