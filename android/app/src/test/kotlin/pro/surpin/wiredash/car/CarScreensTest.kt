package pro.surpin.wiredash.car

import android.os.Looper
import androidx.car.app.HandshakeInfo
import androidx.car.app.OnDoneCallback
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.CarColor
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
import pro.surpin.wiredash.R
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
        var commandWaitForFeedback = false
        var delayCommandReply = false
        val commandReplies = mutableListOf<() -> Unit>()
        val callbacks = mutableListOf<(JSONObject) -> Unit>()
        val commands = mutableListOf<Map<String, Any>>()
        override fun call(method: String, args: Map<String, Any>, done: (JSONObject) -> Unit) {
            if (method == "carCommand") {
                commands.add(args)
                if (commandWaitForFeedback) response.getJSONArray("controls").objects()
                    .first { it.getString("id") == args["controlId"] }.put("pending", args["actionId"])
                val reply = { done(JSONObject().put("outcome", "sent").put("waitForFeedback", commandWaitForFeedback)) }
                if (delayCommandReply) commandReplies.add(reply) else reply()
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

    private fun sending(item: GridItem): Boolean =
        item.image?.icon?.resId == R.drawable.car_sending_0

    private fun checkSelectorBackNavigation(api: Int) {
        context.updateHandshakeInfo(HandshakeInfo("com.google.android.projection.gearhead", api))
        val catalog = JSONObject().put("dashboards", JSONArray().put(JSONObject()
            .put("id", "d").put("name", "Driveway").put("home", "Home")))
        bridge.response = catalog
        val selector = DashboardCarScreen(context, bridge)
        val lifecycle = start(selector)
        val originalType = selector.onGetTemplate().javaClass
        repeat(3) {
            bridge.delayed = true
            shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
            val oldPoll = bridge.callbacks.removeAt(0)
            lifecycle.moveToState(Lifecycle.State.CREATED)
            bridge.delayed = false
            bridge.response = FakeBridge.snapshot()
            val dashboard = if (api >= 8) DashboardControlsCarScreen(context, bridge, "d")
                else ControlsCarScreen(context, bridge, "d")
            val child = start(dashboard)
            dashboard.onGetTemplate()
            bridge.delayed = true
            child.moveToState(Lifecycle.State.DESTROYED)
            lifecycle.moveToState(Lifecycle.State.RESUMED)
            oldPoll(JSONObject().put("outcome", "unreachable"))
            val returned = selector.onGetTemplate()
            assertEquals("Back must preserve the host's template type", originalType, returned.javaClass)
            val rows = if (returned is SectionedItemTemplate) {
                assertFalse(returned.isLoading)
                returned.sections.flatMap { items(it) }
            } else {
                assertFalse((returned as ListTemplate).isLoading)
                returned.singleList!!.items
            }
            assertEquals("Driveway", (rows.single() as Row).title.toString())
            bridge.callbacks.removeAt(0)(JSONObject(catalog.toString()))
            bridge.delayed = false
            bridge.response = catalog
        }
        assertTrue(bridge.commands.isEmpty())
    }

    @Test fun modernBackToSelectorKeepsItsTemplateAndRowsDuringRefresh() = checkSelectorBackNavigation(8)
    @Test fun legacyBackToSelectorKeepsItsRowsDuringRefresh() = checkSelectorBackNavigation(6)

    @Test fun modernCatalogLoadingUsesTheSameTemplateAsItsContent() {
        modernHost()
        bridge.delayed = true
        val screen = DashboardCarScreen(context, bridge)
        start(screen)
        assertTrue((screen.onGetTemplate() as SectionedItemTemplate).isLoading)
    }

    @Test fun modernCurtainPositionButtonsSendSavedActionsAndHighlightReportedPosition() {
        modernHost()
        bridge.response.put("controls", JSONArray().put(JSONObject()
            .put("id", "curtain").put("name", "Curtains").put("kind", "options")
            .put("waitForFeedback", true).put("state", "50")
            .put("actions", JSONArray()
                .put(JSONObject().put("id", "OPTION_0").put("title", "Half open").put("stateMatch", "50").put("icon", "rollerOpen"))
                .put(JSONObject().put("id", "OPTION_1").put("title", "Fully open").put("stateMatch", "100").put("icon", "rollerOpen")))))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        start(screen)
        val buttons = dashboardItems(screen)
        assertEquals(listOf("Half open", "Fully open"), buttons.map { it.title.toString() })
        assertTrue(buttons.all { it.text.toString() == "Curtains" })
        assertEquals(CarColor.GREEN, buttons[0].image!!.tint)
        assertNotEquals(CarColor.GREEN, buttons[1].image!!.tint)
        buttons[1].onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("OPTION_1", bridge.commands.single()["actionId"])
        assertTrue(sending(dashboardItems(screen)[1]))
    }

    @Test fun legacyCurtainPresetsPageAtTheGridLimitWithoutLosingChoices() {
        val limit = context.getCarService(ConstraintManager::class.java)
            .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_GRID)
        val options = JSONArray()
        repeat(limit + 5) { options.put(JSONObject().put("id", "OPTION_$it")
            .put("title", "$it%").put("icon", "rollerOpen")) }
        bridge.response.getJSONArray("controls").getJSONObject(0).put("actions", options)
        val screen = ActionsCarScreen(context, bridge, "d", "gate")
        start(screen)
        val seen = mutableListOf<String>()
        while (true) {
            val buttons = actions(screen)
            assertTrue(buttons.size <= limit)
            seen.addAll(buttons.map { it.title.toString() }.filter { it.endsWith("%") })
            val next = buttons.firstOrNull { it.title.toString() == "Next" } ?: break
            next.onClickDelegate!!.sendClick(done)
            shadowOf(Looper.getMainLooper()).idle()
        }
        assertEquals((0 until limit + 5).map { "$it%" }, seen)
        actions(screen).first { it.title.toString().endsWith("%") }.onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, bridge.commands.size)
    }

    @Test fun coverPercentageSelectionUsesReportedPositionRatherThanDirection() {
        modernHost()
        val cover = bridge.response.getJSONArray("controls").getJSONObject(0)
            .put("position", 50).put("state", "OPEN")
        cover.getJSONArray("actions")
            .put(JSONObject().put("id", "POSITION_50").put("title", "50%")
                .put("position", 50).put("icon", "rollerOpen"))
            .put(JSONObject().put("id", "POSITION_75").put("title", "75%")
                .put("position", 75).put("icon", "rollerOpen"))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        start(screen)
        assertEquals(CarColor.GREEN, dashboardItems(screen)[2].image!!.tint)
        assertNotEquals(CarColor.GREEN, dashboardItems(screen)[3].image!!.tint)
        cover.put("position", JSONObject.NULL)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertNotEquals(CarColor.GREEN, dashboardItems(screen)[2].image!!.tint)
    }

    @Test fun busyTileKeepsItsImageAndClickDelegateWithoutAnimationRedraws() {
        modernHost()
        val controls = JSONArray()
        repeat(40) { controls.put(commandButton("Button $it", if (it < 20) "first" else "second")) }
        bridge.response.put("controls", controls).put("sections", JSONArray()
            .put(JSONObject().put("id", "first").put("name", "First"))
            .put(JSONObject().put("id", "second").put("name", "Second")))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val template = screen.onGetTemplate() as SectionedItemTemplate
        val before = dashboardItems(screen)
        before.last().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        val during = dashboardItems(screen)
        assertEquals(before.map { it.title.toString() }, during.map { it.title.toString() })
        assertTrue(during.dropLast(1).all { !it.isLoading && it.image != null && it.onClickDelegate != null })
        assertTrue(sending(during.last()))
        assertFalse(during.last().isLoading)
        assertNotNull(during.last().image)
        assertSame(before.last().onClickDelegate, during.last().onClickDelegate)
        before.dropLast(1).zip(during.dropLast(1)).forEach { (old, current) ->
            assertSame(old, current)
            assertSame(old.onClickDelegate, current.onClickDelegate)
        }
        val loadingTemplate = screen.onGetTemplate() as SectionedItemTemplate
        assertSame(template.sections[0], loadingTemplate.sections[0])
        assertSame(template.sections[0].itemsDelegate, loadingTemplate.sections[0].itemsDelegate)
        assertNotSame(template.sections[1], loadingTemplate.sections[1])
        // A late host click from the previous snapshot is still rejected.
        before.last().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, bridge.commands.size)
        val submissions = lifecycle.templatesReturned.size
        shadowOf(Looper.getMainLooper()).idleFor(250, TimeUnit.MILLISECONDS)
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertSame(loadingTemplate, screen.onGetTemplate())
        shadowOf(Looper.getMainLooper()).idleFor(750, TimeUnit.MILLISECONDS)
        val after = dashboardItems(screen)
        assertEquals(before.map { it.title.toString() }, after.map { it.title.toString() })
        assertFalse(sending(after.last()))
        assertSame(before.last().onClickDelegate, after.last().onClickDelegate)
        assertEquals(SectionedItemTemplate.SCROLL_STATE_PRESERVE_INDEX,
            (screen.onGetTemplate() as SectionedItemTemplate).scrollStatePersistenceStrategy)
    }

    @Test fun unchangedSnapshotsReuseTemplateAndLazySectionDelegates() {
        modernHost()
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        start(screen)
        val original = screen.onGetTemplate() as SectionedItemTemplate
        repeat(3) {
            shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
            val next = screen.onGetTemplate() as SectionedItemTemplate
            assertSame(original, next)
            assertSame(original.sections.single().itemsDelegate, next.sections.single().itemsDelegate)
        }
        bridge.response.getJSONArray("controls").getJSONObject(0).put("name", "Renamed")
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertNotSame(original, screen.onGetTemplate())
        assertEquals("Renamed", dashboardItems(screen).first().text.toString())
    }

    @Test fun switchFeedbackAndSpinnerCompletionShareOneUpdateAndKeepOtherGroups() {
        modernHost()
        val control = commandButton("Light", "switches").put("kind", "switch").put("state", "ON")
            .put("waitForFeedback", true).put("actions", JSONArray()
                .put(JSONObject().put("id", "ON").put("title", "On").put("icon", "on"))
                .put(JSONObject().put("id", "OFF").put("title", "Off").put("icon", "off")))
        bridge.response.put("controls", JSONArray().put(commandButton("Other", "other")).put(control))
            .put("sections", JSONArray()
                .put(JSONObject().put("id", "other").put("name", "Other controls"))
                .put(JSONObject().put("id", "switches").put("name", "Lights")))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val original = screen.onGetTemplate() as SectionedItemTemplate
        val click = dashboardItems(screen).last().onClickDelegate!!
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("OFF", bridge.commands.single()["actionId"])
        assertTrue(sending(dashboardItems(screen).last()))
        assertFalse(dashboardItems(screen).last().isLoading)
        assertSame(click, dashboardItems(screen).last().onClickDelegate)
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, bridge.commands.size)
        val submissions = lifecycle.templatesReturned.size
        control.put("state", "OFF")
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertEquals(submissions + 1, lifecycle.templatesReturned.size)
        val updated = screen.onGetTemplate() as SectionedItemTemplate
        assertSame(original.sections.first(), updated.sections.first())
        assertFalse(sending(dashboardItems(screen).last()))
        assertEquals(R.drawable.car_off, dashboardItems(screen).last().image!!.icon!!.resId)
        assertSame(click, dashboardItems(screen).last().onClickDelegate)
        // The delegate from before OFF feedback must now send ON.
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("OFF", "ON"), bridge.commands.map { it["actionId"] })
    }

    @Test fun localToBackendPendingDoesNotReplaceTheLoadingSection() {
        modernHost()
        bridge.commandWaitForFeedback = true
        bridge.delayCommandReply = true
        val control = bridge.response.getJSONArray("controls").getJSONObject(0)
            .put("waitForFeedback", true)
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        dashboardItems(screen).first().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        val loading = screen.onGetTemplate() as SectionedItemTemplate
        val submissions = lifecycle.templatesReturned.size
        assertTrue(sending(dashboardItems(screen).first()))
        bridge.commandReplies.removeAt(0)()
        shadowOf(Looper.getMainLooper()).idle()
        assertSame(loading, screen.onGetTemplate())
        assertEquals(submissions, lifecycle.templatesReturned.size)
        shadowOf(Looper.getMainLooper()).idleFor(2, TimeUnit.SECONDS)
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertSame(loading, screen.onGetTemplate())
        control.put("pending", JSONObject.NULL).put("state", "OPEN")
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertEquals(submissions + 1, lifecycle.templatesReturned.size)
        assertFalse(sending(dashboardItems(screen).first()))
    }

    @Test fun intermediatePositionUpdatesDoNotResubmitAnUnchangedGrid() {
        modernHost()
        val control = bridge.response.getJSONArray("controls").getJSONObject(0)
            .put("position", 20)
        control.getJSONArray("actions").put(JSONObject().put("id", "POSITION_50")
            .put("title", "50%").put("position", 50).put("icon", "rollerOpen"))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val original = screen.onGetTemplate()
        val submissions = lifecycle.templatesReturned.size
        control.put("position", 21)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertSame(original, screen.onGetTemplate())
        control.put("position", 50)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertEquals(submissions + 1, lifecycle.templatesReturned.size)
        assertEquals(CarColor.GREEN, dashboardItems(screen).last().image!!.tint)
    }

    @Test fun transientEngineFailureKeepsDashboardAndRecovers() {
        modernHost()
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        start(screen)
        bridge.response = JSONObject().put("outcome", "unreachable")
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertEquals(listOf("Enter", "Exit"), dashboardItems(screen).map { it.title.toString() })
        assertTrue(dashboardItems(screen).all { it.onClickDelegate == null })
        bridge.response = FakeBridge.snapshot()
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertTrue(dashboardItems(screen).all { it.onClickDelegate != null })
    }

    @Test fun cachedSwitchDelegateUsesLatestMqttStateBeforeTheHostRequestsANewTemplate() {
        modernHost()
        val control = commandButton("Light").put("kind", "switch").put("state", "ON")
            .put("actions", JSONArray()
                .put(JSONObject().put("id", "ON").put("title", "On").put("icon", "on"))
                .put(JSONObject().put("id", "OFF").put("title", "Off").put("icon", "off")))
        bridge.response.put("controls", JSONArray().put(control))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        start(screen)
        val click = dashboardItems(screen).single().onClickDelegate!!
        control.put("state", "OFF")
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("ON", bridge.commands.single()["actionId"])
        assertSame(click, dashboardItems(screen).single().onClickDelegate)
    }

    @Test fun retainedDelegatesRejectOfflineRemovedAndHiddenActions() {
        modernHost()
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val click = dashboardItems(screen).first().onClickDelegate!!
        bridge.response.put("connected", false)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        bridge.response.put("connected", true)
        bridge.response.getJSONArray("controls").getJSONObject(0).getJSONArray("actions").remove(0)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        bridge.response = FakeBridge.snapshot()
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        lifecycle.moveToState(Lifecycle.State.CREATED)
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(bridge.commands.isEmpty())
    }

    @Test fun cachedTileClearsTransientTextAndRestoresItsOriginalClickDelegate() {
        modernHost()
        bridge.response.put("controls", JSONArray().put(commandButton("Light")))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        start(screen)
        val original = dashboardItems(screen).single()
        bridge.response.put("connected", false)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertNull(dashboardItems(screen).single().onClickDelegate)
        assertTrue(dashboardItems(screen).single().text.toString().contains("Reconnecting"))
        bridge.response.put("connected", true)
        val control = bridge.response.getJSONArray("controls").getJSONObject(0).put("failed", true)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertTrue(dashboardItems(screen).single().text.toString().contains("Not confirmed"))
        control.put("failed", false)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        val recovered = dashboardItems(screen).single()
        assertEquals("", recovered.text.toString())
        assertSame(original.onClickDelegate, recovered.onClickDelegate)
        recovered.onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("PRESS", bridge.commands.single()["actionId"])
    }

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
        assertTrue(sending(dashboardItems(screen)[1]))
        assertFalse(sending(dashboardItems(screen)[2]))
    }

    @Test fun commandSpinnersAreIndependentAndIgnoreStaleBackendPending() {
        modernHost()
        val a = commandButton("A").put("pending", "PRESS")
        val b = commandButton("B")
        bridge.response.put("controls", JSONArray().put(a).put(b))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        start(screen)
        assertFalse(sending(dashboardItems(screen)[0]))
        dashboardItems(screen)[0].onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idleFor(100, TimeUnit.MILLISECONDS)
        dashboardItems(screen)[1].onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idleFor(899, TimeUnit.MILLISECONDS)
        assertTrue(dashboardItems(screen).all { sending(it) })
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.MILLISECONDS)
        assertFalse(sending(dashboardItems(screen)[0]))
        assertTrue(sending(dashboardItems(screen)[1]))
        shadowOf(Looper.getMainLooper()).idleFor(100, TimeUnit.MILLISECONDS)
        assertTrue(dashboardItems(screen).none { sending(it) })
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
        assertTrue(sending(dashboardItems(screen).first()))
        bridge.delayed = true
        lifecycle.moveToState(Lifecycle.State.CREATED)
        lifecycle.moveToState(Lifecycle.State.RESUMED)
        val old = bridge.callbacks.removeAt(0)
        lifecycle.moveToState(Lifecycle.State.CREATED)
        lifecycle.moveToState(Lifecycle.State.RESUMED)
        old(JSONObject().put("outcome", "error"))
        bridge.callbacks.removeAt(0)(FakeBridge.snapshot())
        assertFalse(sending(dashboardItems(screen).first()))
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
