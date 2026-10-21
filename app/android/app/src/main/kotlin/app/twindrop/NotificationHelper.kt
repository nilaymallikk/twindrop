package app.twindrop

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import kotlin.math.absoluteValue

/**
 * Native notifications for the persistent keep-alive service and for incoming items
 * while the UI is closed (docs/06 §2).
 *
 * Channel ids are part of the UI contract: `keepalive` (minimum importance, silent,
 * persistent) and `messages` (heads-up). No message text is ever logged here.
 */
object NotificationHelper {
    const val CHANNEL_KEEPALIVE = "keepalive"
    const val CHANNEL_MESSAGES = "messages"

    const val KEEPALIVE_NOTIFICATION_ID = 1001
    private const val MESSAGE_ID_BASE = 2000

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val keepAlive = NotificationChannel(
            CHANNEL_KEEPALIVE,
            "Connection to desktop",
            NotificationManager.IMPORTANCE_MIN,
        ).apply {
            description = "Keeps the private connection to your desktop alive."
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        manager.createNotificationChannel(keepAlive)

        val messages = NotificationChannel(
            CHANNEL_MESSAGES,
            "Messages",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "New messages and links from your desktop."
            setShowBadge(true)
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        manager.createNotificationChannel(messages)
    }

    fun canPostNotifications(context: Context): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled()

    private fun contentIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun pauseAction(context: Context, paused: Boolean): PendingIntent {
        val intent = Intent(context, KeepAliveService::class.java).apply {
            action = KeepAliveService.ACTION_TOGGLE_PAUSE
        }
        return PendingIntent.getService(
            context,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * "TwinDrop · connected to <desktop>" while connected; the copy is truthful
     * about the other states instead of pretending a connection exists.
     */
    fun buildKeepAliveNotification(
        context: Context,
        desktopName: String?,
        connected: Boolean,
        paused: Boolean,
    ): Notification {
        val title = when {
            paused -> "TwinDrop · paused"
            !desktopName.isNullOrBlank() -> "TwinDrop · connected to $desktopName"
            else -> "TwinDrop · waiting for your desktop"
        }
        val text = when {
            paused -> "Paused. Messages stay queued until you resume."
            connected -> "Connected on your Wi-Fi. Tap to open TwinDrop."
            else -> "Waiting for your desktop. Tap to open TwinDrop."
        }
        val actionLabel = if (paused) "Resume" else "Pause"
        return NotificationCompat.Builder(context, CHANNEL_KEEPALIVE)
            .setSmallIcon(R.drawable.ic_stat_twindrop)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(contentIntent(context))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .addAction(0, actionLabel, pauseAction(context, paused))
            .build()
    }

    fun showMessageNotification(context: Context, deviceName: String?, preview: String) {
        if (!Prefs.notificationsEnabled(context)) return
        if (!canPostNotifications(context)) return
        val safePreview = preview.replace('\n', ' ').replace('\r', ' ').trim()
        if (safePreview.isEmpty()) return
        val shown = if (safePreview.length > 80) safePreview.take(80) + "…" else safePreview
        val title = deviceName?.takeIf { it.isNotBlank() } ?: "TwinDrop"
        val intent = contentIntent(context)
        val notification = NotificationCompat.Builder(context, CHANNEL_MESSAGES)
            .setSmallIcon(R.drawable.ic_stat_twindrop)
            .setContentTitle(title)
            .setContentText(shown)
            .setStyle(NotificationCompat.BigTextStyle().bigText(shown))
            .setContentIntent(intent)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        val id = MESSAGE_ID_BASE + (title + shown).hashCode().absoluteValue % 1000
        try {
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS denied: do not crash the keep-alive service.
        }
    }
}
