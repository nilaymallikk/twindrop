package app.twindrop

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Translucent bottom-sheet panel shown right after a share (docs/06 §1).
 *
 * Holds a FlutterActivity whose engine runs the `sharePanelMain` Dart entrypoint.
 * The engine is cached in [TwindropApp] so a second share is warm. The panel is
 * auto-dismissed after ~4 s; Undo / Change category / Also send as chat are handled
 * by the Dart UI, which calls `finishPanel` on this activity's channel.
 */
class SharePanelActivity : FlutterActivity() {
    private var dismissHandler: Handler? = null
    private var autoDismissMs: Long = DEFAULT_AUTO_DISMISS_MS
    private var panelChannel: MethodChannel? = null
    private var channelsRegistered = false
    private var currentShareId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        val payload = buildPayload(intent)
        currentShareId = payload?.get("shareId") as? String
        if (currentShareId == null) {
            super.onCreate(savedInstanceState)
            finish()
            return
        }
        PanelSession.attach(this, payload)
        autoDismissMs = (payload["autoDismissMs"] as? Number)?.toLong() ?: DEFAULT_AUTO_DISMISS_MS
        super.onCreate(savedInstanceState)
        scheduleDismiss()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = buildPayload(intent) ?: return
        currentShareId = payload["shareId"] as? String ?: currentShareId
        PanelSession.attach(this, payload)
        autoDismissMs = (payload["autoDismissMs"] as? Number)?.toLong() ?: DEFAULT_AUTO_DISMISS_MS
        panelChannel?.invokeMethod("panelChanged", payload)
        scheduleDismiss()
    }

    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine? =
        TwindropApp.instance?.panelEngine(this)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun getDartEntrypointFunctionName(): String = "sharePanelMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!channelsRegistered) {
            TwindropChannels.registerCore(flutterEngine, applicationContext, this)
            panelChannel = TwindropChannels.registerPanel(
                flutterEngine,
                applicationContext,
                this,
            )[TwindropChannels.SHARE_PANEL]
            channelsRegistered = true
        }
        val payload = PanelSession.currentPayload()
        panelChannel?.invokeMethod("panelShown", payload)
    }

    override fun onDestroy() {
        dismissHandler?.removeCallbacksAndMessages(null)
        PanelSession.detach(this)
        super.onDestroy()
    }

    @Deprecated("FlutterActivity uses onBackPressed for the panel root")
    override fun onBackPressed() {
        finishWithAction("dismiss")
    }

    fun scheduleDismiss() {
        val handler = dismissHandler ?: Handler(Looper.getMainLooper()).also { dismissHandler = it }
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({ finishWithAction("auto") }, autoDismissMs)
    }

    fun finishWithAction(action: String) {
        PanelSession.lastAction = action
        dismissHandler?.removeCallbacksAndMessages(null)
        if (!isFinishing) finish()
    }

    private fun buildPayload(intent: Intent?): Map<String, Any?>? {
        val shareId = intent?.getStringExtra(EXTRA_SHARE_ID) ?: return null
        val item = ShareQueueStore.get(this, shareId)
        val text = item?.text
        return mapOf(
            "shareId" to shareId,
            "text" to (text ?: ""),
            "subject" to item?.subject,
            "title" to item?.title,
            "sourcePackage" to item?.sourcePackage,
            "receivedAtMs" to item?.receivedAtMs,
            "duplicate" to (intent.getBooleanExtra(EXTRA_DUPLICATE, false)),
            "autoDismissMs" to DEFAULT_AUTO_DISMISS_MS,
            "defaultAction" to Prefs.shareDefaultAction(this),
            "paired" to Prefs.isPaired(this),
            "desktopName" to Prefs.desktopName(this),
            "notificationsAllowed" to NotificationHelper.canPostNotifications(this),
        )
    }

    companion object {
        const val EXTRA_SHARE_ID = "app.twindrop.extra.SHARE_ID"
        const val EXTRA_DUPLICATE = "app.twindrop.extra.DUPLICATE"
        const val DEFAULT_AUTO_DISMISS_MS = 4_000L
    }
}

/**
 * Bridge between the (single, cached) panel engine and whichever panel activity is
 * currently attached. The engine outlives the activity, so the payload and activity
 * reference live here rather than on the Activity instance.
 */
object PanelSession {
    @Volatile
    private var activityRef: java.lang.ref.WeakReference<SharePanelActivity>? = null

    @Volatile
    private var payload: Map<String, Any?> = emptyMap()

    @Volatile
    var lastAction: String? = null
        internal set

    fun attach(activity: SharePanelActivity, next: Map<String, Any?>) {
        activityRef = java.lang.ref.WeakReference(activity)
        payload = next
        lastAction = null
    }

    fun detach(activity: SharePanelActivity) {
        if (activityRef?.get() === activity) {
            activityRef = null
        }
    }

    fun currentPayload(): Map<String, Any?> = payload

    fun payloadMap(activity: Activity?): Map<String, Any?> = payload

    fun finish(action: String) {
        activityRef?.get()?.finishWithAction(action)
    }
}
