package pro.surpin.wiredash

import android.os.Handler
import android.os.Looper
import pro.surpin.wiredash.wireguard.wgbridge.Route
import pro.surpin.wiredash.wireguard.wgbridge.Wgbridge
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors

/** One channel per Flutter engine; closing an engine releases all its routes. */
class WireGuardPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val routes = mutableMapOf<String, Route>() // worker thread only
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "zigdash/wireguard").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in setOf("validate", "open", "close")) {
            result.notImplemented()
            return
        }
        worker.execute {
            try {
                val answer: Any? = when (call.method) {
                    "validate" -> {
                        Wgbridge.validate(requireNotNull(call.argument<String>("config")))
                        null
                    }
                    "open" -> {
                        val route = Wgbridge.start(
                            requireNotNull(call.argument<String>("config")),
                            requireNotNull(call.argument<String>("host")),
                            requireNotNull(call.argument<Int>("port")).toLong(),
                            (call.argument<Int>("timeoutMs") ?: 15000).toLong(),
                        )
                        val id = UUID.randomUUID().toString()
                        routes[id] = route
                        mapOf("id" to id, "port" to route.port().toInt(), "token" to route.token())
                    }
                    else -> {
                        routes.remove(call.argument<String>("id"))?.close()
                        null
                    }
                }
                main.post { result.success(answer) }
            } catch (e: Exception) {
                // The Go bridge emits redacted validation errors. Never log
                // MethodCall.arguments: they contain WireGuard private keys.
                main.post { result.error("wireguard", e.message ?: "WireGuard operation failed", null) }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        worker.execute {
            routes.values.forEach { it.close() }
            routes.clear()
        }
        worker.shutdown()
    }
}
