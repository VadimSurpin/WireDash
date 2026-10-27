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
