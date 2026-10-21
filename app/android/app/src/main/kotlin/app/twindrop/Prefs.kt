package app.twindrop

import android.content.Context

/**
 * Local settings that the native shell needs. Message/note content never lives here;
 * only booleans and the desktop display name used in the persistent notification.
 */
object Prefs {
    private const val FILE = "twindrop_prefs"

    private const val KEY_KEEPALIVE_ENABLED = "keepalive.enabled"
    private const val KEY_KEEPALIVE_PAUSED = "keepalive.paused"
    private const val KEY_DESKTOP_NAME = "peer.desktopName"
    private const val KEY_NOTIFICATIONS_ENABLED = "notifications.enabled"
    private const val KEY_SHARE_DEFAULT_ACTION = "share.defaultAction"
    private const val KEY_HIDE_ON_BLUR = "desktop.hideOnBlur"

    const val SHARE_ACTION_NOTEPAD = "notepad"
    const val SHARE_ACTION_CHAT = "chat"
    const val SHARE_ACTION_ASK = "ask"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun isKeepAliveEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_KEEPALIVE_ENABLED, false)

    fun setKeepAliveEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_KEEPALIVE_ENABLED, enabled).commit()
    }

    fun isPaused(context: Context): Boolean = prefs(context).getBoolean(KEY_KEEPALIVE_PAUSED, false)

    fun setPaused(context: Context, paused: Boolean) {
        prefs(context).edit().putBoolean(KEY_KEEPALIVE_PAUSED, paused).commit()
    }

    fun desktopName(context: Context): String? =
        prefs(context).getString(KEY_DESKTOP_NAME, null)?.takeIf { it.isNotBlank() }

    fun setDesktopName(context: Context, name: String?) {
        prefs(context).edit().putString(KEY_DESKTOP_NAME, name?.takeIf { it.isNotBlank() }).commit()
    }

    fun isPaired(context: Context): Boolean = desktopName(context) != null

    fun notificationsEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_NOTIFICATIONS_ENABLED, true)

    fun setNotificationsEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_NOTIFICATIONS_ENABLED, enabled).commit()
    }

    fun shareDefaultAction(context: Context): String =
        prefs(context).getString(KEY_SHARE_DEFAULT_ACTION, SHARE_ACTION_NOTEPAD)
            ?: SHARE_ACTION_NOTEPAD

    fun hideOnBlur(context: Context): Boolean = prefs(context).getBoolean(KEY_HIDE_ON_BLUR, true)
}
