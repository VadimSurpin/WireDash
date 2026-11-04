package pro.surpin.wiredash

import android.os.Handler
import android.os.Looper
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@LooperMode(LooperMode.Mode.PAUSED)
class ShortcutRequestsTest {
    @Test fun missingDartReadyTimesOutAndIgnoresTheAbandonedStartup() {
        val callbacks = mutableListOf<() -> Unit>()
        val results = mutableListOf<String>()
        val invoked = mutableListOf<String>()
        var stops = 0
        val requests = ShortcutRequests(Handler(Looper.getMainLooper()), { ok, _ -> callbacks.add(ok) },
            { method, _, done -> invoked.add(method); done("ok") }, { stops++ }, 2_000)
        requests.call("carCatalog", emptyMap(), 12_000, results::add)
        shadowOf(Looper.getMainLooper()).idleFor(2, TimeUnit.SECONDS)
        assertEquals(listOf("{\"outcome\":\"error\"}"), results)
        assertEquals(1, stops)
        requests.call("carCatalog", emptyMap(), 12_000, results::add)
        callbacks[0]()
        assertTrue(invoked.isEmpty())
        callbacks[1]()
        assertEquals(listOf("carCatalog"), invoked)
        assertEquals("ok", results.last())
        shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS)
        assertEquals(1, stops)
    }

    @Test fun stalledReadReplacesTheDeadEngineWithoutReplayingAnInflightCommand() {
        var starts = 0
        var stops = 0
        val invoked = mutableListOf<String>()
        val replies = mutableListOf<(String) -> Unit>()
        val results = mutableListOf<String>()
        val requests = ShortcutRequests(Handler(Looper.getMainLooper()), { ok, _ -> starts++; ok() },
            { method, _, done -> invoked.add(method); replies.add(done) }, { stops++ })
        requests.call("carCommand", emptyMap(), 30_000, results::add)
        requests.call("carOpen", emptyMap(), 1_000, results::add)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertEquals(1, stops)
        assertEquals(2, results.size)
        replies.forEach { it("late") }
        assertEquals(2, results.size)
        requests.call("carCatalog", emptyMap(), 12_000, results::add)
        assertEquals(2, starts)
        assertEquals(listOf("carCommand", "carOpen", "carCatalog"), invoked)
        replies.last()("ok")
        assertEquals("ok", results.last())
    }

    @Test fun commandTimeoutDoesNotRestartOrReplayTheEngine() {
        var stops = 0
        val invoked = mutableListOf<String>()
        val results = mutableListOf<String>()
        val requests = ShortcutRequests(Handler(Looper.getMainLooper()), { ok, _ -> ok() },
            { method, _, done -> invoked.add(method); if (method == "carCatalog") done("ok") }, { stops++ })
        requests.call("carCommand", emptyMap(), 1_000, results::add)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        requests.call("carCatalog", emptyMap(), 12_000, results::add)
        assertEquals(0, stops)
        assertEquals(listOf("carCommand", "carCatalog"), invoked)
        assertEquals(listOf("{\"outcome\":\"unreachable\"}", "ok"), results)
    }

    @Test fun warmingWithoutARequestCannotLeaveStartupStuckForever() {
        var starts = 0
        var stops = 0
        val requests = ShortcutRequests(Handler(Looper.getMainLooper()), { _, _ -> starts++ },
            { _, _, _ -> fail("Dart never became ready") }, { stops++ }, 2_000)
        requests.warm()
        shadowOf(Looper.getMainLooper()).idleFor(2, TimeUnit.SECONDS)
        requests.warm()
        assertEquals(2, starts)
        assertEquals(1, stops)
    }

    @Test fun coldStartLeavesMainThreadResponsiveAndStartsOnlyOnce() {
        var starts = 0
        lateinit var ready: () -> Unit
        val invoked = mutableListOf<String>()
        val results = mutableListOf<String>()
        val main = Handler(Looper.getMainLooper())
        val requests = ShortcutRequests(main, { ok, _ -> starts++; ready = ok },
            { method, _, done -> invoked.add(method); done("ok") })
        requests.warm()
        requests.call("carCatalog", emptyMap(), 12_000, results::add)
        requests.call("carOpen", emptyMap(), 12_000, results::add)
        var responsive = false
        main.post { responsive = true }
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(responsive)
        assertEquals(1, starts)
        assertTrue(invoked.isEmpty())
        ready()
        assertEquals(listOf("carCatalog", "carOpen"), invoked)
        assertEquals(listOf("ok", "ok"), results)
    }

    @Test fun expiredColdCommandIsNeverDispatchedWhenDartEventuallyStarts() {
        lateinit var ready: () -> Unit
        val invoked = mutableListOf<String>()
        val results = mutableListOf<String>()
        val requests = ShortcutRequests(Handler(Looper.getMainLooper()), { ok, _ -> ready = ok },
            { method, _, done -> invoked.add(method); done("sent") })
        requests.call("carCommand", emptyMap(), 12_000, results::add)
        shadowOf(Looper.getMainLooper()).idleFor(12, TimeUnit.SECONDS)
        assertEquals(listOf("{\"outcome\":\"unreachable\"}"), results)
        ready()
        assertTrue(invoked.isEmpty())
        requests.call("carCatalog", emptyMap(), 12_000, results::add)
        assertEquals(listOf("carCatalog"), invoked)
    }

    @Test fun lateReplyCompletesOnceAndStartupFailureCanBeRetried() {
        var starts = 0
        lateinit var reply: (String) -> Unit
        val results = mutableListOf<String>()
        val requests = ShortcutRequests(Handler(Looper.getMainLooper()), { ok, fail ->
            starts++
            if (starts == 1) fail() else ok()
        }, { _, _, done -> reply = done })
        requests.call("carCatalog", emptyMap(), 12_000, results::add)
        assertEquals(listOf("{\"outcome\":\"error\"}"), results)
        requests.call("carOpen", emptyMap(), 12_000, results::add)
        shadowOf(Looper.getMainLooper()).idleFor(12, TimeUnit.SECONDS)
        reply("sent")
        assertEquals(2, results.size)
        assertEquals("{\"outcome\":\"unreachable\"}", results.last())
        assertEquals(2, starts)
    }
}
