package app.twindrop

import android.app.Application
import android.content.Context
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Process-wide owner of the Flutter engines that are not tied to MainActivity.
 *
 * The share panel engine is created once and cached: a second share reuses the warm
 * `sharePanelMain` isolate instead of paying a cold start (docs/06 §1, SHARE-009).
 * [SharePanelActivity] supplies it through `provideFlutterEngine` and never destroys it
 * (`shouldDestroyEngineWithHost` is false).
 */
class TwindropApp : Application() {
    private var cachedPanelEngine: FlutterEngine? = null
    private var panelEngineGroup: FlutterEngineGroup? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        installCrashHandler()
        Log.i(TAG, "application created")
        try {
            // Channels must exist before the first notification is built, whichever engine starts first.
            NotificationHelper.ensureChannels(this)
            Log.i(TAG, "notification channels ready")
        } catch (t: Throwable) {
            // A missing notification channel must never stop the app from starting.
            Log.e(TAG, "could not create the notification channels", t)
        }
        Log.i(TAG, "application onCreate done")
    }

    /**
     * Logs any uncaught native crash with the app's own tag, so `logcat` shows
     * where the app died instead of only a stack trace with no context.
     */
    private fun installCrashHandler() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            Log.e(TAG, "uncaught exception on ${thread.name}", error)
            previous?.uncaughtException(thread, error)
        }
    }

    /**
     * The cached share-panel engine. Returns null if the engine cannot be created, in which
     * case FlutterActivity builds its own engine for the panel instead.
     */
    @Synchronized
    fun panelEngine(context: Context): FlutterEngine? {
        cachedPanelEngine?.let { return it }
        return try {
            val appContext = context.applicationContext
            val group = panelEngineGroup
                ?: FlutterEngineGroup(appContext).also { panelEngineGroup = it }
            group.createAndRunEngine(
                FlutterEngineGroup.Options(appContext)
                    .setDartEntrypoint(dartEntrypoint(ENTRYPOINT_SHARE_PANEL))
                    .setAutomaticallyRegisterPlugins(true),
            ).also { cachedPanelEngine = it }
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * Creates an engine without an Activity and runs [entrypoint] after [configure] has
     * registered its channels, so Dart's first channel call cannot miss a handler.
     * Used by [KeepAliveService] for `keepAliveMain`; the caller owns [FlutterEngine.destroy].
     */
    @Synchronized
    fun createHeadlessEngine(entrypoint: String, configure: (FlutterEngine) -> Unit): FlutterEngine {
        val engine = FlutterEngine(this)
        try {
            configure(engine)
        } catch (t: Throwable) {
            engine.destroy()
            throw t
        }
        engine.dartExecutor.executeDartEntrypoint(dartEntrypoint(entrypoint))
        return engine
    }

    private fun dartEntrypoint(functionName: String): DartExecutor.DartEntrypoint =
        DartExecutor.DartEntrypoint(
            FlutterInjector.instance().flutterLoader().findAppBundlePath(),
            functionName,
        )

    companion object {
        @Volatile
        var instance: TwindropApp? = null
            private set

        const val ENTRYPOINT_SHARE_PANEL = "sharePanelMain"
        const val ENTRYPOINT_KEEP_ALIVE = "keepAliveMain"

        /** Logcat tag for every startup milestone and crash. */
        const val TAG = "TwinDrop"
    }
}
