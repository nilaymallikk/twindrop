package app.twindrop

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Main UI activity. singleTask: a second launch (notification tap, launcher) returns to
 * the existing task. Share intents that land here are forwarded to Dart; the share
 * sheet itself targets [ShareReceiverActivity].
 */
class MainActivity : FlutterActivity() {
    private var networkChannel: MethodChannel? = null
    private var shareQueueChannel: MethodChannel? = null
    private var networkMonitor: NetworkMonitor? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val registration = TwindropChannels.registerCore(
            flutterEngine,
            applicationContext,
            this,
        ) { networkMonitor?.current() ?: emptyMap() }
        shareQueueChannel = registration[TwindropChannels.SHARE_QUEUE]
        networkChannel = registration[TwindropChannels.NETWORK]
        if (networkMonitor == null) {
            networkMonitor = NetworkMonitor(this) { state ->
                networkChannel?.invokeMethod("networkChanged", state)
            }
        }
        (networkMonitor as NetworkMonitor?)?.start()
        // Tell Dart immediately if the app was cold-started by a share intent.
        pendingShare()?.let { pending ->
            shareQueueChannel?.invokeMethod("onShareReceived", pending)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NotificationHelper.ensureChannels(this)
        if (savedInstanceState == null) handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    override fun onDestroy() {
        networkMonitor?.stop()
        networkMonitor = null
        super.onDestroy()
    }

    private fun handleShareIntent(intent: Intent?) {
        val parsed = ShareIntents.parse(intent)
        if (parsed !is ShareIntents.ParseResult.Ok) return
        val enqueued = ShareQueueStore.enqueue(
            this,
            parsed.text,
            parsed.subject,
            parsed.title,
            intent?.`package`,
        ) ?: return
        val payload = enqueued.item.toMap() + mapOf(
            "duplicate" to enqueued.duplicate,
            "alreadyImported" to enqueued.alreadyImported,
        )
        pendingSharePayload = payload
        shareQueueChannel?.invokeMethod("onShareReceived", payload)
    }

    companion object {
        @Volatile
        private var pendingSharePayload: Map<String, Any?>? = null

        /** Cold-start handshake: Dart reads this once after its channel handler is ready. */
        fun consumePendingShareId(): String? {
            val id = pendingSharePayload?.get("shareId") as? String
            pendingSharePayload = null
            return id
        }

        private fun pendingShare(): Map<String, Any?>? = pendingSharePayload
    }
}
