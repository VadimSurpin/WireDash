package pro.surpin.wiredash

import android.os.Handler

/** Main-thread requests may wait for Dart, but never block the car host or run after timeout. */
internal class ShortcutRequests(
    private val main: Handler,
    private val start: (ready: () -> Unit, failed: () -> Unit) -> Unit,
    private val invoke: (String, Map<String, Any>, (String) -> Unit) -> Unit,
    private val stop: () -> Unit = {},
    private val startupTimeoutMs: Long = 20_000,
) {
    private class Request(val method: String, val args: Map<String, Any>, val done: (String) -> Unit) {
        var active = true
        lateinit var timeout: Runnable
    }
    private val pending = mutableListOf<Request>()
    private val active = mutableSetOf<Request>()
    private var ready = false
    private var starting = false
    private var generation = 0
    private var startupTimeout: Runnable? = null

    fun warm() {
        if (ready || starting) return
        starting = true
        val attempt = ++generation
        startupTimeout = Runnable { if (starting && generation == attempt) reset() }
            .also { main.postDelayed(it, startupTimeoutMs) }
        try {
            start({
                if (!starting || generation != attempt) return@start
                startupTimeout?.let(main::removeCallbacks)
                startupTimeout = null
                starting = false
                ready = true
                val queued = pending.toList()
                pending.clear()
                queued.forEach(::dispatch)
            }, {
                if (starting && generation == attempt) reset()
            })
        } catch (_: Exception) {
            if (generation == attempt) reset()
        } catch (_: LinkageError) {
            if (generation == attempt) reset()
        }
    }

    fun call(method: String, args: Map<String, Any>, timeoutMs: Long, done: (String) -> Unit) {
        val request = Request(method, args, done)
        active.add(request)
        request.timeout = Runnable {
            // A dead Dart isolate can leave its channel registered forever.
            // Only read timeouts invalidate it; commands are never retried.
            val stalledRead = ready && method in setOf("carCatalog", "carOpen")
            if (stalledRead) reset("{\"outcome\":\"unreachable\"}")
            else finish(request, "{\"outcome\":\"unreachable\"}")
        }
        main.postDelayed(request.timeout, timeoutMs)
        if (ready) dispatch(request)
        else {
            pending.add(request)
            warm()
        }
    }

    private fun reset(result: String = "{\"outcome\":\"error\"}") {
        generation++
        ready = false
        starting = false
        startupTimeout?.let(main::removeCallbacks)
        startupTimeout = null
        // Detach before completing requests: callbacks may request a new engine.
        try { stop() } finally { active.toList().forEach { finish(it, result) } }
    }

    private fun dispatch(request: Request) {
        if (!request.active) return
        try {
            invoke(request.method, request.args) { finish(request, it) }
        } catch (_: Exception) {
            finish(request, "{\"outcome\":\"error\"}")
        }
    }

    private fun finish(request: Request, result: String) {
        if (!request.active) return
        request.active = false
        active.remove(request)
        pending.remove(request)
        main.removeCallbacks(request.timeout)
        request.done(result)
    }
}
