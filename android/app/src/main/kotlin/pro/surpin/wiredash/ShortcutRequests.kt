package pro.surpin.wiredash

import android.os.Handler

/** Main-thread requests may wait for Dart, but never block the car host or run after timeout. */
internal class ShortcutRequests(
    private val main: Handler,
    private val start: (ready: () -> Unit, failed: () -> Unit) -> Unit,
    private val invoke: (String, Map<String, Any>, (String) -> Unit) -> Unit,
) {
    private class Request(val method: String, val args: Map<String, Any>, val done: (String) -> Unit) {
        var active = true
        lateinit var timeout: Runnable
    }
    private val pending = mutableListOf<Request>()
    private var ready = false
    private var starting = false

    fun warm() {
        if (ready || starting) return
        starting = true
        try {
            start({
                starting = false
                ready = true
                val queued = pending.toList()
                pending.clear()
                queued.forEach(::dispatch)
            }, {
                starting = false
                ready = false
                pending.toList().forEach { finish(it, "{\"outcome\":\"error\"}") }
            })
        } catch (_: Exception) {
            starting = false
            pending.toList().forEach { finish(it, "{\"outcome\":\"error\"}") }
        }
    }

    fun call(method: String, args: Map<String, Any>, timeoutMs: Long, done: (String) -> Unit) {
        val request = Request(method, args, done)
        request.timeout = Runnable { finish(request, "{\"outcome\":\"unreachable\"}") }
        main.postDelayed(request.timeout, timeoutMs)
        if (ready) dispatch(request)
        else {
            pending.add(request)
            warm()
        }
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
        pending.remove(request)
        main.removeCallbacks(request.timeout)
        request.done(result)
    }
}
