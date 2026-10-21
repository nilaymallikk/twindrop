package app.twindrop

import android.app.Application
import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterInjector

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
        // Channels must exist before the first notification is built, whichever engine starts first.
        NotificationHelper.ensureChannels(this)
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
    }
}
