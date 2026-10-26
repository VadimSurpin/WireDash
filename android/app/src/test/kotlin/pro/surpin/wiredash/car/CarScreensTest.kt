package pro.surpin.wiredash.car

import android.os.Looper
import androidx.car.app.HandshakeInfo
import androidx.car.app.OnDoneCallback
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Item
import androidx.car.app.model.Section
import androidx.car.app.model.SectionedItemTemplate
import androidx.car.app.serialization.Bundleable
import androidx.car.app.testing.ScreenController
import androidx.car.app.testing.TestCarContext
import androidx.lifecycle.Lifecycle
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@LooperMode(LooperMode.Mode.PAUSED)
class CarScreensTest {
    private lateinit var context: TestCarContext
    private lateinit var bridge: FakeBridge
    private val controllers = mutableListOf<ScreenController>()
    private val done = object : OnDoneCallback {}

    private class FakeBridge : CarBridge {
        var response = snapshot()
        var delayed = false
        val callbacks = mutableListOf<(JSONObject) -> Unit>()
        val commands = mutableListOf<Map<String, Any>>()
        override fun call(method: String, args: Map<String, Any>, done: (JSONObject) -> Unit) {
            if (method == "carCommand") {
                commands.add(args)
                done(JSONObject().put("outcome", "sent").put("waitForFeedback", false))
            } else if (delayed) callbacks.add(done)
            else done(JSONObject(response.toString()))
        }
        companion object {
            fun snapshot(connected: Boolean = true): JSONObject = JSONObject()
                .put("id", "d").put("name", "Driveway").put("connected", connected)
                .put("controls", JSONArray().put(JSONObject()
                    .put("id", "gate").put("name", "Gate").put("kind", "cover")
                    .put("waitForFeedback", false).put("state", JSONObject.NULL)
                    .put("pending", JSONObject.NULL).put("failed", false)
                    .put("actions", JSONArray()
                        .put(JSONObject().put("id", "OPEN").put("title", "Enter").put("icon", "gatePartial"))
                        .put(JSONObject().put("id", "CLOSE").put("title", "Exit").put("icon", "gateClosed")))))
        }
    }

    @Before fun setup() {
        context = TestCarContext.createCarContext(RuntimeEnvironment.getApplication())
        context.updateHandshakeInfo(HandshakeInfo("com.google.android.projection.gearhead", 6))
        bridge = FakeBridge()
    }
    @After fun cleanup() {
        controllers.reversed().forEach { it.moveToState(Lifecycle.State.DESTROYED) }
    }
    private fun start(screen: Screen): ScreenController = ScreenController(screen).also {
        controllers.add(it)
        it.moveToState(Lifecycle.State.RESUMED)
        shadowOf(Looper.getMainLooper()).idle()
    }
    private fun actions(screen: ActionsCarScreen): List<GridItem> =
        (screen.onGetTemplate() as GridTemplate).singleList!!.items.map { it as GridItem }

    private fun modernHost() {
        context.updateHandshakeInfo(HandshakeInfo("com.google.android.projection.gearhead", 8))
    }

    @Suppress("UNCHECKED_CAST")
    private fun items(section: Section<*>): List<Item> {
        val delegate = section.itemsDelegate
        if (delegate.size == 0) return emptyList()
        var result: List<Item>? = null
        delegate.requestItemRange(0, delegate.size - 1, object : OnDoneCallback {
            override fun onSuccess(response: Bundleable?) { result = response!!.get() as List<Item> }
            override fun onFailure(response: Bundleable) { fail("Host item request failed: ${response.get()}") }
        })
        shadowOf(Looper.getMainLooper()).idle()
        return requireNotNull(result)
    }

    private fun dashboardItems(screen: DashboardControlsCarScreen): List<GridItem> =
        (screen.onGetTemplate() as SectionedItemTemplate).sections.flatMap { items(it) }.map { it as GridItem }

    private fun commandButton(id: String, section: String? = null): JSONObject = JSONObject()
        .put("id", id).put("name", id).put("kind", "button").put("sectionId", section)
        .put("waitForFeedback", false).put("state", JSONObject.NULL)
        .put("pending", JSONObject.NULL).put("failed", false)
        .put("actions", JSONArray().put(JSONObject().put("id", "PRESS").put("title", id).put("icon", "on")))

    @Test fun modernDashboardShowsSavedGroupsWithDirectGateButtons() {
        modernHost()
        val gate = bridge.response.getJSONArray("controls").getJSONObject(0).put("sectionId", "gates")
        bridge.response.put("sections", JSONArray()
            .put(JSONObject().put("id", "gates").put("name", "Gates"))
            .put(JSONObject().put("id", "lights").put("name", "Lights")))
            .put("controls", JSONArray().put(commandButton("Loose"))
                .put(gate).put(commandButton("Driveway light", "lights")))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        start(screen)
        val template = screen.onGetTemplate() as SectionedItemTemplate
        assertEquals(listOf(null, "Gates", "Lights"), template.sections.map { it.title?.toString() })
        assertEquals(SectionedItemTemplate.SCROLL_STATE_PRESERVE_INDEX, template.scrollStatePersistenceStrategy)
        val buttons = dashboardItems(screen)
        assertEquals(listOf("Loose", "Enter", "Exit", "Driveway light"), buttons.map { it.title.toString() })
        assertEquals("Gate", buttons[1].text.toString())
        buttons[1].onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("OPEN", bridge.commands.single()["actionId"])
        assertEquals("gate", bridge.commands.single()["controlId"])
        assertTrue(dashboardItems(screen)[1].isLoading)
        assertFalse(dashboardItems(screen)[2].isLoading)
    }

    @Test fun commandSpinnersAreIndependentAndIgnoreStaleBackendPending() {
        modernHost()
        val a = commandButton("A").put("pending", "PRESS")
        val b = commandButton("B")
        bridge.response.put("controls", JSONArray().put(a).put(b))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        start(screen)
        assertFalse(dashboardItems(screen)[0].isLoading)
        dashboardItems(screen)[0].onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idleFor(100, TimeUnit.MILLISECONDS)
        dashboardItems(screen)[1].onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idleFor(899, TimeUnit.MILLISECONDS)
        assertTrue(dashboardItems(screen).all { it.isLoading })
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.MILLISECONDS)
        assertFalse(dashboardItems(screen)[0].isLoading)
        assertTrue(dashboardItems(screen)[1].isLoading)
        shadowOf(Looper.getMainLooper()).idleFor(100, TimeUnit.MILLISECONDS)
        assertTrue(dashboardItems(screen).none { it.isLoading })
        dashboardItems(screen)[0].onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("A", "B", "A"), bridge.commands.map { it["controlId"] })
    }

    @Test fun modernSwitchUsesOneTileAndSendsTheOppositeOfItsState() {
        modernHost()
        val control = commandButton("Light").put("kind", "switch").put("state", "ON")
            .put("waitForFeedback", true).put("actions", JSONArray()
                .put(JSONObject().put("id", "ON").put("title", "On").put("icon", "on"))
                .put(JSONObject().put("id", "OFF").put("title", "Off").put("icon", "off")))
        bridge.response.put("controls", JSONArray().put(control))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        start(screen)
        assertEquals("Light", dashboardItems(screen).single().title.toString())
        dashboardItems(screen).single().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("OFF", bridge.commands.single()["actionId"])
    }

    @Test fun modernScrollingExposesAllButtonsAndCatalogRowsWithoutPageItems() {
        modernHost()
        val limit = context.getCarService(ConstraintManager::class.java)
            .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_GRID)
        val count = limit + 25
        val controls = JSONArray()
        repeat(count) { controls.put(commandButton("Button $it")) }
        bridge.response.put("controls", controls)
        val dashboard = DashboardControlsCarScreen(context, bridge, "d")
        start(dashboard)
        assertEquals(count, dashboardItems(dashboard).size)
        dashboardItems(dashboard).last().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("Button ${count - 1}", bridge.commands.single()["controlId"])

        val dashboards = JSONArray()
        repeat(count) { dashboards.put(JSONObject().put("id", "$it").put("name", "Dashboard $it").put("home", "Home")) }
        bridge.response = JSONObject().put("dashboards", dashboards)
        val catalog = DashboardCarScreen(context, bridge)
        start(catalog)
        val template = catalog.onGetTemplate() as SectionedItemTemplate
        val rows = template.sections.flatMap { items(it) }.map { it as Row }
        assertEquals(count, rows.size)
        assertEquals("Dashboard ${count - 1}", rows.last().title.toString())
        assertTrue(rows.none { it.title.toString() in listOf("Next", "Previous") })
        assertEquals(SectionedItemTemplate.SCROLL_STATE_PRESERVE_INDEX, template.scrollStatePersistenceStrategy)
    }

    @Test fun modernDashboardResumeClearsSpinnersAndIgnoresOldCallbacks() {
        modernHost()
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        dashboardItems(screen).first().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(dashboardItems(screen).first().isLoading)
        bridge.delayed = true
        lifecycle.moveToState(Lifecycle.State.CREATED)
        lifecycle.moveToState(Lifecycle.State.RESUMED)
        val old = bridge.callbacks.removeAt(0)
        lifecycle.moveToState(Lifecycle.State.CREATED)
        lifecycle.moveToState(Lifecycle.State.RESUMED)
        old(JSONObject().put("outcome", "error"))
        bridge.callbacks.removeAt(0)(FakeBridge.snapshot())
        assertFalse(dashboardItems(screen).first().isLoading)
    }

    @Test fun modernDisconnectedDashboardHasNoClickableActions() {
        modernHost()
        bridge.response = FakeBridge.snapshot(false)
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        start(screen)
        assertTrue(dashboardItems(screen).all { it.onClickDelegate == null && it.text.toString().contains("Reconnecting") })
        assertTrue(bridge.commands.isEmpty())
    }

    @Test fun gateUsesConfiguredButtonsAndSpinnerThenAllowsAnotherPulse() {
        val screen = ActionsCarScreen(context, bridge, "d", "gate")
        start(screen)
        assertEquals(listOf("Enter", "Exit"), actions(screen).map { it.title.toString() })
        actions(screen).first().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("OPEN", bridge.commands.single()["actionId"])
        assertTrue(actions(screen).first().isLoading)
        assertNull(actions(screen).first().image)
        assertNull(actions(screen).first().onClickDelegate)
        shadowOf(Looper.getMainLooper()).idleFor(999, TimeUnit.MILLISECONDS)
        assertTrue(actions(screen).first().isLoading)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.MILLISECONDS)
        assertFalse(actions(screen).first().isLoading)
        actions(screen).first().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(2, bridge.commands.size)
    }

    @Test fun disconnectedActionsShowReconnectingAndCannotSend() {
        bridge.response = FakeBridge.snapshot(false)
        val screen = ActionsCarScreen(context, bridge, "d", "gate")
        start(screen)
        assertTrue(actions(screen).all { it.onClickDelegate == null })
        assertTrue(actions(screen).all { it.text.toString().contains("Reconnecting") })
        assertTrue(bridge.commands.isEmpty())
    }

    @Test fun carSessionResumeIgnoresCallbacksFromBeforeItWasHidden() {
        bridge.delayed = true
        val screen = ActionsCarScreen(context, bridge, "d", "gate")
        val lifecycle = start(screen)
        val old = bridge.callbacks.removeAt(0)
        lifecycle.moveToState(Lifecycle.State.CREATED)
        lifecycle.moveToState(Lifecycle.State.RESUMED)
        old(JSONObject().put("outcome", "error"))
        bridge.callbacks.removeAt(0)(FakeBridge.snapshot())
        assertEquals(2, actions(screen).size)
    }

    @Test fun hidingDuringSpinnerDoesNotLeaveItStuckAfterResume() {
        val screen = ActionsCarScreen(context, bridge, "d", "gate")
        val lifecycle = start(screen)
        actions(screen).first().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(actions(screen).first().isLoading)
        lifecycle.moveToState(Lifecycle.State.CREATED)
        lifecycle.moveToState(Lifecycle.State.RESUMED)
        assertFalse(actions(screen).first().isLoading)
    }

    @Test fun emptyCatalogExplainsPhoneSetupAndDoesNotExposeEditors() {
        bridge.response = JSONObject().put("dashboards", JSONArray())
        val screen = DashboardCarScreen(context, bridge)
        start(screen)
        assertTrue(screen.onGetTemplate() is MessageTemplate)
        assertTrue(bridge.commands.isEmpty())
    }

    @Test fun listsPageAtTheActualHostLimitWithoutDroppingControls() {
        val limit = context.getCarService(ConstraintManager::class.java)
            .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
        val rows = JSONArray()
        repeat(limit + 3) { rows.put(JSONObject().put("id", "$it").put("name", "Dashboard $it").put("home", "Home")) }
        bridge.response = JSONObject().put("dashboards", rows)
        val screen = DashboardCarScreen(context, bridge)
        start(screen)
        val first = (screen.onGetTemplate() as ListTemplate).singleList!!.items
        assertTrue(first.size <= limit)
        assertEquals("Next", (first.last() as Row).title.toString())
        (first.last() as Row).onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        val next = (screen.onGetTemplate() as ListTemplate).singleList!!.items
        assertTrue(next.size <= limit)
        assertEquals("Previous", (next.first() as Row).title.toString())
    }
}
