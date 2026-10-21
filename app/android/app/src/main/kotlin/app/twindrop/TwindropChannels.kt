package app.twindrop

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The single place that defines the Dart <-> native channel contract for Android.
 *
 * Channels (see app/lib/platform/android/):
 *   twindrop/share_queue    durable native share queue, read/ack/launch share id
 *   twindrop/keepalive      foreground service start/stop/status/locks/battery helper
 *   twindrop/keepalive_host events pushed into the headless keep-alive isolate
 *   twindrop/network        network state + pushed networkChanged events
 *   twindrop/app            version, device info, runtime permission helpers
 *   twindrop/notifications  message notifications (works from the headless engine)
 *   twindrop/share_panel    payload + finish for SharePanelActivity's Flutter UI
 */
object TwindropChannels {
    const val SHARE_QUEUE = "twindrop/share_queue"
    const val KEEPALIVE = "twindrop/keepalive"
    const val KEEPALIVE_HOST = "twindrop/keepalive_host"
    const val NETWORK = "twindrop/network"
    const val APP = "twindrop/app"
    const val NOTIFICATIONS = "twindrop/notifications"
    const val SHARE_PANEL = "twindrop/share_panel"

    const val REQUEST_NOTIFICATIONS = 7101

    class Registration(val channels: Map<String, MethodChannel>) {
        operator fun get(name: String): MethodChannel? = channels[name]
    }

    /**
     * Registers all channels that both the UI engine and the headless keep-alive engine
     * need. [activity] is null inside KeepAliveService.
     */
    fun registerCore(
        engine: FlutterEngine,
        context: Context,
        activity: Activity?,
        networkProvider: (() -> Map<String, Any?>)? = null,
    ): Registration {
        val messenger = engine.dartExecutor.binaryMessenger
        val channels = mutableMapOf<String, MethodChannel>()
        fun channel(name: String): MethodChannel =
            channels.getOrPut(name) { MethodChannel(messenger, name) }

        channel(SHARE_QUEUE).setMethodCallHandler { call, result ->
            when (call.method) {
                "readPending" -> result.success(
                    ShareQueueStore.readPending(context).map { it.toMap() },
                )

                "get" -> {
                    val id = call.argument<String>("shareId")
                    if (id == null) {
                        result.error("bad_args", "shareId is required", null)
                    } else {
                        result.success(ShareQueueStore.get(context, id)?.toMap())
                    }
                }

                "ack" -> {
                    val ids = call.argument<List<String>>("shareIds") ?: emptyList()
                    ShareQueueStore.ack(context, ids)
                    result.success(true)
                }

                "consumeLaunchShareId" -> result.success(MainActivity.consumePendingShareId())

                else -> result.notImplemented()
            }
        }

        channel(KEEPALIVE).setMethodCallHandler { call, result ->
            when (call.method) {
                "isRunning" -> result.success(KeepAliveService.isRunning())

                "isEnabled" -> result.success(Prefs.isKeepAliveEnabled(context))

                "isPaused" -> result.success(Prefs.isPaused(context))

                "start" -> {
                    val desktopName = call.argument<String>("desktopName")
                    val paused = call.argument<Boolean>("paused")
                    Prefs.setKeepAliveEnabled(context, true)
                    if (desktopName != null) Prefs.setDesktopName(context, desktopName)
                    if (paused != null) Prefs.setPaused(context, paused)
                    result.success(KeepAliveService.start(context))
                }

                "stop" -> {
                    Prefs.setKeepAliveEnabled(context, false)
                    KeepAliveService.stop(context)
                    result.success(true)
                }

                "setStatus" -> {
                    val desktopName = call.argument<String?>("desktopName")
                    val connected = call.argument<Boolean>("connected") ?: false
                    val paused = call.argument<Boolean>("paused")
                    if (desktopName != null) Prefs.setDesktopName(context, desktopName)
                    if (paused != null) Prefs.setPaused(context, paused)
                    KeepAliveService.updateStatus(context, desktopName, connected)
                    result.success(true)
                }

                "setPaused" -> {
                    val paused = call.argument<Boolean>("paused") ?: false
                    Prefs.setPaused(context, paused)
                    KeepAliveService.updateStatus(context, Prefs.desktopName(context), connected = !paused)
                    result.success(true)
                }

                "isBatteryOptimizationIgnored" -> result.success(isIgnoringBatteryOptimizations(context))

                "requestIgnoreBatteryOptimizations" -> {
                    if (activity == null) {
                        result.error("no_activity", "Needs an activity", null)
                    } else {
                        result.success(requestIgnoreBatteryOptimizations(activity))
                    }
                }

                "acquireMulticastLock" -> result.success(MulticastLocks.acquire(context))

                "releaseMulticastLock" -> {
                    MulticastLocks.release()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        channel(NETWORK).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrent" -> result.success(
                    networkProvider?.invoke() ?: mapOf(
                        "online" to false,
                        "wifi" to false,
                        "cellular" to false,
                        "ethernet" to false,
                        "vpn" to false,
                    ),
                )

                else -> result.notImplemented()
            }
        }

        channel(APP).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVersion" -> result.success(appVersion(context))

                "getPlatformInfo" -> result.success(platformInfo(context))

                "areNotificationsEnabled" -> result.success(NotificationHelper.canPostNotifications(context))

                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        if (activity == null) {
                            result.success(NotificationHelper.canPostNotifications(context))
                        } else {
                            if (ContextCompat.checkSelfPermission(
                                    activity,
                                    Manifest.permission.POST_NOTIFICATIONS,
                                ) != PackageManager.PERMISSION_GRANTED
                            ) {
                                ActivityCompat.requestPermissions(
                                    activity,
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    REQUEST_NOTIFICATIONS,
                                )
                            }
                            result.success(NotificationHelper.canPostNotifications(context))
                        }
                    } else {
                        result.success(NotificationHelper.canPostNotifications(context))
                    }
                }

                "openNotificationSettings" -> {
                    result.success(openNotificationSettings(context, activity))
                }

                "openBatteryOptimizationSettings" -> {
                    result.success(openBatteryOptimizationSettings(context, activity))
                }

                else -> result.notImplemented()
            }
        }

        channel(NOTIFICATIONS).setMethodCallHandler { call, result ->
            when (call.method) {
                "showMessage" -> {
                    val deviceName = call.argument<String>("deviceName")
                    val preview = call.argument<String>("preview") ?: ""
                    NotificationHelper.showMessageNotification(context, deviceName, preview)
                    result.success(true)
                }

                "canPost" -> result.success(NotificationHelper.canPostNotifications(context))

                else -> result.notImplemented()
            }
        }

        return Registration(channels)
    }

    /** Registers the channel used only by the share panel's Flutter entrypoint. */
    fun registerPanel(
        engine: FlutterEngine,
        context: Context,
        activity: Activity,
    ): Registration {
        val messenger = engine.dartExecutor.binaryMessenger
        val panelChannel = MethodChannel(messenger, SHARE_PANEL)
        panelChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPanelPayload" -> result.success(PanelSession.payloadMap(activity))
                "finishPanel" -> {
                    val action = call.argument<String>("action") ?: "done"
                    PanelSession.finish(action)
                    result.success(true)
                }
                "getDefaultShareAction" -> result.success(Prefs.shareDefaultAction(context))
                else -> result.notImplemented()
            }
        }
        return Registration(mapOf(SHARE_PANEL to panelChannel))
    }

    fun appVersion(context: Context): Map<String, Any?> {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        @Suppress("DEPRECATION")
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }
        return mapOf(
            "packageName" to context.packageName,
            "versionName" to (info.versionName ?: "0.0.0"),
            "versionCode" to code,
        )
    }

    fun platformInfo(context: Context): Map<String, Any?> = mapOf(
        "os" to "android",
        "model" to Build.MODEL,
        "manufacturer" to Build.MANUFACTURER,
        "androidSdkInt" to Build.VERSION.SDK_INT,
        "isEmulator" to (
            Build.FINGERPRINT.startsWith("generic") ||
                Build.FINGERPRINT.contains("emulator") ||
                Build.PRODUCT.contains("sdk") ||
                Build.HARDWARE.contains("goldfish")
            ),
        "locale" to context.resources.configuration.locales[0]?.toLanguageTag(),
    )

    private fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun requestIgnoreBatteryOptimizations(activity: Activity): Boolean {
        return try {
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${activity.packageName}"),
            )
            activity.startActivity(intent)
            true
        } catch (_: Exception) {
            openBatteryOptimizationSettings(activity, activity)
        }
    }

    private fun openBatteryOptimizationSettings(context: Context, activity: Activity?): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            (activity ?: context).startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openNotificationSettings(context: Context, activity: Activity?): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            (activity ?: context).startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                val fallback = Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:${context.packageName}"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                (activity ?: context).startActivity(fallback)
                true
            } catch (_: Exception) {
                false
            }
        }
    }
}
