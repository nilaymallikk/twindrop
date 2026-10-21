package app.twindrop

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground service that keeps the pinned WSS connection to the paired desktop alive while
 * the UI is closed (docs/06 §2). It hosts a headless engine running `keepAliveMain`, so the
 * connection uses the same Dart ConnectionManager as the UI; no protocol code lives here.
 *
 * The notification is the user's control surface: tap opens the app, Pause/Resume flips the
 * same preference Dart reads on its next status push. No message content is ever logged.
 */
class KeepAliveService : Service() {
    private var engine: FlutterEngine? = null
    private var networkMonitor: NetworkMonitor? = null
    private var networkChannel: MethodChannel? = null

    @Volatile
    private var connected = false

    @Volatile
    private var desktopName: String? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        active = this
        desktopName = Prefs.desktopName(this)
        NotificationHelper.ensureChannels(this)
        // Must happen within 5 s of startForegroundService; do it before engine startup.
        showForegroundNotification()
        startHeadlessEngine()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_TOGGLE_PAUSE -> {
                val paused = !Prefs.isPaused(this)
                Prefs.setPaused(this, paused)
                showForegroundNotification()
            }

            else -> Unit
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        running = false
        active = null
        networkMonitor?.stop()
        networkMonitor = null
        networkChannel = null
        MulticastLocks.release()
        engine?.destroy()
        engine = null
        super.onDestroy()
    }

    private fun startHeadlessEngine() {
        if (engine != null) return
        val app = TwindropApp.instance ?: return
        engine = try {
            app.createHeadlessEngine(TwindropApp.ENTRYPOINT_KEEP_ALIVE) { headless ->
                val registration = TwindropChannels.registerCore(
                    headless,
                    applicationContext,
                    activity = null,
                    networkProvider = { networkMonitor?.current() ?: emptyMap() },
                )
                networkChannel = registration[TwindropChannels.NETWORK]
                networkMonitor = NetworkMonitor(this) { state ->
                    networkChannel?.invokeMethod("networkChanged", state)
                }.also { it.start() }
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun applyStatus(name: String?, isConnected: Boolean) {
        desktopName = name
        connected = isConnected
        showForegroundNotification()
    }

    private fun showForegroundNotification() {
        val notification = NotificationHelper.buildKeepAliveNotification(
            this,
            desktopName,
            connected,
            Prefs.isPaused(this),
        )
        try {
            ServiceCompat.startForeground(
                this,
                NotificationHelper.KEEPALIVE_NOTIFICATION_ID,
                notification,
                foregroundServiceType(),
            )
        } catch (_: Exception) {
            // POST_NOTIFICATIONS denied (API 33+) or an FGS restriction: keep the connection
            // running without crashing. Android surfaces the service in its own UI.
        }
    }

    private fun foregroundServiceType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }

    companion object {
        const val ACTION_START = "app.twindrop.action.KEEPALIVE_START"
        const val ACTION_STOP = "app.twindrop.action.KEEPALIVE_STOP"
        const val ACTION_TOGGLE_PAUSE = "app.twindrop.action.KEEPALIVE_TOGGLE_PAUSE"

        @Volatile
        private var running = false

        @Volatile
        private var active: KeepAliveService? = null

        /** Starts (or reuses) the service. False when Android forbids a background FGS start. */
        fun start(context: Context): Boolean {
            val appContext = context.applicationContext
            return try {
                ContextCompat.startForegroundService(
                    appContext,
                    Intent(appContext, KeepAliveService::class.java).setAction(ACTION_START),
                )
                true
            } catch (_: Exception) {
                false
            }
        }

        fun stop(context: Context) {
            val appContext = context.applicationContext
            try {
                appContext.stopService(Intent(appContext, KeepAliveService::class.java))
            } catch (_: Exception) {
                // Already stopped.
            }
        }

        fun isRunning(): Boolean = running

        /** Mirrors connection state into the persistent notification. No-op when stopped. */
        fun updateStatus(context: Context, desktopName: String?, connected: Boolean) {
            active?.applyStatus(desktopName, connected)
        }
    }
}
