package pro.surpin.wiredash

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * The headless command engine shared by widgets, Quick Settings tiles and
 * Device Controls (docs/design/roadmap-post-2.0.md, 2.1 §1): one cached
 * FlutterEngine running lib/shortcuts/shortcut_engine.dart. Calls made before
 * Dart is ready wait in a queue. Main thread only.
 */
object ShortcutEngine {
    private const val TAG = "ZigDashShortcuts"
    private const val ID = "shortcuts"
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private var requests: ShortcutRequests? = null

    private fun requests(app: Context): ShortcutRequests = requests ?: ShortcutRequests(main,
        { ready, failed -> start(app, ready, failed) },
        { method, args, done ->
            channel!!.invokeMethod(method, args, object : MethodChannel.Result {
                override fun success(result: Any?) = done(result as? String ?: "{}")
                override fun error(code: String, msg: String?, details: Any?) {
                    Log.e(TAG, "$method failed: $code")
                    done("{\"outcome\":\"error\"}")
                }
                override fun notImplemented() = done("{\"outcome\":\"error\"}")
            })
        }).also { requests = it }

    /** Starts the engine early (a tile does this when the panel opens). */
    fun warm(ctx: Context) = onMain { requests(ctx.applicationContext).warm() }

    fun toggle(ctx: Context, connectionId: String, ieee: String, done: (String) -> Unit) =
        call(ctx, "toggle", mapOf("connectionId" to connectionId, "ieee" to ieee), done)

    /** A shutter's OPEN, STOP or CLOSE. */
    fun cover(ctx: Context, connectionId: String, ieee: String, action: String, done: (String) -> Unit) =
        call(ctx, "cover", mapOf("connectionId" to connectionId, "ieee" to ieee, "action" to action), done)

    /** A shutter's position, 0–100. */
    fun position(ctx: Context, connectionId: String, ieee: String, position: Int, done: (String) -> Unit) =
        call(ctx, "position", mapOf("connectionId" to connectionId, "ieee" to ieee, "position" to position), done)

    /** Device Controls: on or off. */
    fun set(ctx: Context, connectionId: String, ieee: String, on: Boolean, done: (String) -> Unit) =
        call(ctx, "set", mapOf("connectionId" to connectionId, "ieee" to ieee, "on" to on), done)

    /** Device Controls' slider: a shutter's position or a light's brightness. */
    fun level(ctx: Context, connectionId: String, ieee: String, level: Int, done: (String) -> Unit) =
        call(ctx, "level", mapOf("connectionId" to connectionId, "ieee" to ieee, "level" to level), done)

    /** Asks [ieees] for their state and follows them for a while. */
    fun watch(ctx: Context, connectionId: String, ieees: List<String>, done: (String) -> Unit) =
        call(ctx, "watch", mapOf("connectionId" to connectionId, "ieees" to ieees), done)

    fun scene(ctx: Context, connectionId: String, sceneId: String, done: (String) -> Unit) =
        call(ctx, "scene", mapOf("connectionId" to connectionId, "sceneId" to sceneId), done)

    /** Android Auto uses the same headless engine and private WireGuard stack. */
    fun car(ctx: Context, method: String, args: Map<String, Any>, done: (String) -> Unit) {
        require(method in setOf("carCatalog", "carOpen", "carCommand", "carClose", "carReconnect"))
        onMain { requests(ctx.applicationContext).call(method, args, 12_000, done) }
    }

    fun forgetHome(ctx: Context, connectionId: String, done: (String) -> Unit) {
        if (channel == null) done("{}")
        else call(ctx, "forgetHome", mapOf("connectionId" to connectionId), done)
    }

    private fun call(ctx: Context, method: String, args: Map<String, Any>, done: (String) -> Unit) {
        onMain { requests(ctx.applicationContext).call(method, args, 30_000, done) }
    }

    private fun start(app: Context, ready: () -> Unit, failed: () -> Unit) {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        // Loading the VM/unpacking assets can take seconds on a cold phone.
        // Waiting synchronously here blocks CarAppService's main/Binder thread.
        loader.ensureInitializationCompleteAsync(app, null, main) {
            try { startDart(app, loader.findAppBundlePath(), ready) }
            catch (error: Exception) {
                Log.e(TAG, "Headless engine startup failed", error)
                FlutterEngineCache.getInstance().get(ID)?.destroy()
                FlutterEngineCache.getInstance().remove(ID)
                channel = null
                failed()
            }
        }
    }

    private fun startDart(app: Context, bundle: String, ready: () -> Unit) {
        val engine = FlutterEngine(app)
        FlutterEngineCache.getInstance().put(ID, engine)
        if (!engine.plugins.has(WireGuardPlugin::class.java)) engine.plugins.add(WireGuardPlugin())
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, "zigdash/shortcuts")
        ch.setMethodCallHandler { call, result ->
            result.success(null)
            if (call.method == "ready") ready()
        }
        channel = ch
        // Library-qualified: an entrypoint outside main.dart isn't found by
        // name alone.
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
            bundle,
            "package:wiredash/shortcuts/shortcut_engine.dart", "shortcutEngine"))
    }

    fun onMain(block: () -> Unit) = Handler(Looper.getMainLooper()).post(block)
}
