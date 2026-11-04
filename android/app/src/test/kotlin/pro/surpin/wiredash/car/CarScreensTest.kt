package pro.surpin.wiredash.car

import android.os.IBinder
import android.os.IInterface
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
import androidx.car.app.model.OnClickDelegate
import androidx.car.app.model.Row
import androidx.car.app.model.Item
import androidx.car.app.model.Section
import androidx.car.app.model.SectionedItemTemplate
import androidx.car.app.serialization.Bundleable
import androidx.car.app.testing.ScreenController
import androidx.car.app.testing.TestAppManager
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
        var commandOutcome = "sent"
        var delayCommandReply = false
        val commandReplies = mutableListOf<() -> Unit>()
        val callbacks = mutableListOf<(JSONObject) -> Unit>()
        val commands = mutableListOf<Map<String, Any>>()
        override fun call(method: String, args: Map<String, Any>, done: (JSONObject) -> Unit) {
            if (method == "carCommand") {
                commands.add(args)
                if (commandWaitForFeedback) response.getJSONArray("controls").objects()
                    .first { it.getString("id") == args["controlId"] }.put("pending", args["actionId"])
                val reply = { done(JSONObject().put("outcome", commandOutcome).put("waitForFeedback", commandWaitForFeedback)) }
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

    private fun listRows(screen: DashboardListCarScreen): List<Row> =
        (screen.onGetTemplate() as ListTemplate).sectionedLists.flatMap { it.itemList.items }.map { it as Row }

    private fun commandButton(id: String, section: String? = null): JSONObject = JSONObject()
        .put("id", id).put("name", id).put("kind", "button").put("sectionId", section)
        .put("waitForFeedback", false).put("state", JSONObject.NULL)
        .put("pending", JSONObject.NULL).put("failed", false)
        .put("actions", JSONArray().put(JSONObject().put("id", "PRESS").put("title", id).put("icon", "on")))

    // Lazy item requests serialize and deserialize GridItems, creating new
    // model/delegate wrappers. Compare the actual IPC endpoint, not wrappers.
    private fun clickBinder(delegate: OnClickDelegate?): IBinder {
        val value = requireNotNull(delegate)
        val listener = value.javaClass.getDeclaredField("mListener").apply { isAccessible = true }
            .get(value) as IInterface
        return listener.asBinder()
    }

    private fun toasts(): List<String> =
        context.getCarService(TestAppManager::class.java).toastsShown.map { it.toString() }

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
            val dashboard = if (api >= 8) DashboardListCarScreen(context, bridge, "d")
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

    @Test fun groupedListIsSelectedByModernCatalogAndKeepsItsLoadingType() {
        modernHost()
        bridge.response = JSONObject().put("dashboards", JSONArray().put(JSONObject()
            .put("id", "d").put("name", "Driveway").put("home", "Home")))
        val selector = DashboardCarScreen(context, bridge)
        start(selector)
        val entry = items((selector.onGetTemplate() as SectionedItemTemplate).sections.single()).single() as Row
        bridge.delayed = true
        entry.onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        val child = context.getCarService(androidx.car.app.ScreenManager::class.java).top
        assertTrue(child is DashboardListCarScreen)
        start(child)
        assertTrue((child.onGetTemplate() as ListTemplate).isLoading)
        bridge.callbacks.forEach { it(FakeBridge.snapshot()) }
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse((child.onGetTemplate() as ListTemplate).isLoading)
    }

    @Test fun groupedListKeepsSavedGroupsAndPairsGateActionsInOneRow() {
        modernHost()
        bridge.response.getJSONArray("controls").getJSONObject(0).put("sectionId", "gates")
        bridge.response.getJSONArray("controls").put(commandButton("Light", "lights"))
            .put(commandButton("Orphan", "deleted"))
        bridge.response.put("sections", JSONArray()
            .put(JSONObject().put("id", "lights").put("name", "Lights"))
            .put(JSONObject().put("id", "empty").put("name", "Empty"))
            .put(JSONObject().put("id", "gates").put("name", "Gates")))
        val screen = DashboardListCarScreen(context, bridge, "d")
        start(screen)
        val groups = (screen.onGetTemplate() as ListTemplate).sectionedLists
        assertEquals(listOf("Controls", "Lights", "Gates"), groups.map { it.header.toString() })
        assertEquals(listOf("Orphan", "Light", "Gate"), listRows(screen).map { it.title.toString() })
        val gate = listRows(screen).last()
        assertEquals(listOf("Enter", "Exit"), gate.actions.map { it.title.toString() })
        assertTrue(gate.actions.all { it.icon != null })
        assertEquals("Enter · Exit", gate.texts.single().toString())
    }

    @Test fun groupedListProgressKeepsRowsDelegatesAndAllowsRepeatPulses() {
        modernHost()
        val screen = DashboardListCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val original = screen.onGetTemplate()
        val gate = listRows(screen).single()
        val submissions = lifecycle.templatesReturned.size
        gate.actions[0].onClickDelegate!!.sendClick(done)
        gate.actions[0].onClickDelegate!!.sendClick(done)
        gate.actions[1].onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("OPEN", "CLOSE"), bridge.commands.map { it["actionId"] })
        assertEquals(2, toasts().size)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertSame(original, screen.onGetTemplate())
        assertSame(gate, listRows(screen).single())
        gate.actions[0].onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("OPEN", "CLOSE", "OPEN"), bridge.commands.map { it["actionId"] })
    }

    @Test fun groupedListNativeToggleReflectsPhoneStateAndUsesLatestValue() {
        modernHost()
        val light = commandButton("Light").put("kind", "switch").put("waitForFeedback", true).put("state", "OFF")
            .put("actions", JSONArray()
                .put(JSONObject().put("id", "ON").put("title", "On").put("icon", "on"))
                .put(JSONObject().put("id", "OFF").put("title", "Off").put("icon", "off")))
        bridge.response.put("controls", JSONArray().put(light))
        val screen = DashboardListCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val before = listRows(screen).single()
        assertFalse(before.toggle!!.isChecked)
        val submissions = lifecycle.templatesReturned.size
        light.put("state", "ON") // Phone-origin feedback; no Auto tap.
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        val after = listRows(screen).single()
        assertTrue(after.toggle!!.isChecked)
        assertEquals(before.title, after.title)
        assertEquals(CarColor.GREEN, after.image!!.tint)
        assertEquals(submissions + 1, lifecycle.templatesReturned.size)
        assertTrue(bridge.commands.isEmpty())
        before.toggle!!.onCheckedChangeDelegate.sendCheckedChange(true, done)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue("An old toggle cannot re-send the already reported state", bridge.commands.isEmpty())
        after.toggle!!.onCheckedChangeDelegate.sendCheckedChange(false, done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("OFF", bridge.commands.single()["actionId"])
    }

    @Test fun groupedListReconnectUsesPopupAndRetainedActionsRejectOfflineTaps() {
        modernHost()
        val screen = DashboardListCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val original = screen.onGetTemplate()
        val retained = listRows(screen).single().actions.first()
        val submissions = lifecycle.templatesReturned.size
        bridge.response.put("connected", false)
        shadowOf(Looper.getMainLooper()).idleFor(2, TimeUnit.SECONDS)
        assertSame(original, screen.onGetTemplate())
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertEquals(listOf(context.getString(R.string.car_reconnecting)), toasts())
        retained.onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(bridge.commands.isEmpty())
        assertEquals(2, toasts().size)
        bridge.response.put("connected", true)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        retained.onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("OPEN", bridge.commands.single()["actionId"])
    }

    @Test fun groupedListKeepsStopAndEveryPresetWithAtMostTwoActionsPerRow() {
        modernHost()
        val gate = bridge.response.getJSONArray("controls").getJSONObject(0)
        val actions = gate.getJSONArray("actions")
        actions.put(JSONObject().put("id", "STOP").put("title", "Stop").put("icon", "stop"))
        repeat(5) { actions.put(JSONObject().put("id", "POSITION_$it").put("title", "${it * 25}%")
            .put("stateMatch", "${it * 25}").put("icon", "rollerOpen")) }
        gate.put("state", "50")
        val screen = DashboardListCarScreen(context, bridge, "d")
        start(screen)
        val rows = listRows(screen)
        assertTrue(rows.all { it.actions.size <= 2 && it.title.toString() == "Gate" })
        assertEquals(listOf("Enter", "Exit"), rows.first().actions.map { it.title.toString() })
        val buttons = rows.flatMap { it.actions }
        assertEquals(listOf("Enter", "Exit", "Stop", "0%", "25%", "50%", "75%", "100%"), buttons.map { it.title.toString() })
        assertEquals(CarColor.GREEN, buttons[5].icon!!.tint)
        buttons[5].onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("POSITION_2", bridge.commands.single()["actionId"])
    }

    @Test fun groupedListPagesAtHostLimitWithoutLosingGroupsOrResettingOnProgress() {
        modernHost()
        val limit = context.getCarService(ConstraintManager::class.java)
            .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST).coerceIn(3, 100)
        val count = limit + 5
        val controls = JSONArray()
        repeat(count) { controls.put(commandButton("Button $it", if (it < count / 2) "a" else "b")) }
        bridge.response.put("controls", controls).put("sections", JSONArray()
            .put(JSONObject().put("id", "a").put("name", "First"))
            .put(JSONObject().put("id", "b").put("name", "Second")))
        val screen = DashboardListCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val seen = mutableListOf<String>()
        while (true) {
            val current = listRows(screen)
            assertTrue(current.size <= limit)
            seen.addAll(current.filter { it.title.toString().startsWith("Button ") }.map { it.title.toString() })
            val next = current.firstOrNull { it.title.toString() == context.getString(R.string.car_next) } ?: break
            next.onClickDelegate!!.sendClick(done)
            shadowOf(Looper.getMainLooper()).idle()
        }
        assertEquals((0 until count).map { "Button $it" }, seen)
        val lastPage = screen.onGetTemplate()
        val submissions = lifecycle.templatesReturned.size
        listRows(screen).first().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertSame(lastPage, screen.onGetTemplate())
        assertEquals(submissions, lifecycle.templatesReturned.size)
        listRows(screen).last().onClickDelegate!!.sendClick(done) // Previous.
        shadowOf(Looper.getMainLooper()).idle()
        assertNotSame(lastPage, screen.onGetTemplate())
    }

    @Test fun groupedListRetainedActionsRejectRemovedControlsAndHiddenScreens() {
        modernHost()
        val screen = DashboardListCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val retained = listRows(screen).single().actions.first()
        bridge.response.put("controls", JSONArray().put(commandButton("Other")))
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        retained.onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(bridge.commands.isEmpty())
        val button = listRows(screen).single()
        lifecycle.moveToState(Lifecycle.State.CREATED)
        button.onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(bridge.commands.isEmpty())
    }

    @Test fun groupedListVideoRemainsBrowsableWithoutBrokerOrCommands() {
        modernHost()
        bridge.response = FakeBridge.snapshot(false).put("controls", JSONArray().put(JSONObject()
            .put("id", "camera").put("name", "Camera").put("kind", "video")
            .put("waitForFeedback", false).put("actions", JSONArray().put(JSONObject()
                .put("id", "VIEW").put("title", "Video").put("icon", "video")))))
        val screen = DashboardListCarScreen(context, bridge, "d")
        start(screen)
        val row = listRows(screen).single()
        assertTrue(row.isBrowsable)
        assertTrue(toasts().isEmpty())
        row.onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(bridge.commands.isEmpty())
        assertTrue(context.getCarService(androidx.car.app.ScreenManager::class.java).top.onGetTemplate() is MessageTemplate)
    }

    @Test fun modernVideoRemainsBrowsableOfflineAndNeverSendsMqttCommand() {
        modernHost()
        bridge.response = FakeBridge.snapshot(false).put("controls", JSONArray().put(JSONObject()
            .put("id", "camera").put("name", "Driveway camera").put("kind", "video")
            .put("waitForFeedback", false).put("actions", JSONArray().put(JSONObject()
                .put("id", "VIEW").put("title", "Video").put("icon", "video")))))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        start(screen)
        val tile = dashboardItems(screen).single()
        assertEquals("Driveway camera", tile.title.toString())
        assertEquals(context.getString(R.string.car_video_phone), tile.text.toString())
        assertTrue(toasts().isEmpty())
        tile.onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(bridge.commands.isEmpty())
        val info = context.getCarService(androidx.car.app.ScreenManager::class.java).top
        val template = info.onGetTemplate() as MessageTemplate
        assertEquals(context.getString(R.string.car_video_limit), template.message.toString())
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
        assertFalse(sending(dashboardItems(screen)[1]))
        assertEquals(1, toasts().size)
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

    @Test fun commandProgressToastNeverReplacesTheScrollingGrid() {
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
        val submissions = lifecycle.templatesReturned.size
        before.last().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("Button 39 · Sending…"), toasts())
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertSame(template, screen.onGetTemplate())
        val during = dashboardItems(screen)
        before.zip(during).forEach { (old, current) ->
            assertEquals(old, current)
            assertFalse(current.isLoading)
            assertFalse(sending(current))
            assertSame(clickBinder(old.onClickDelegate), clickBinder(current.onClickDelegate))
        }
        // The pressed section and its remote list remain stable too. Previous
        // tests allowed precisely this section to be replaced, missing the jump.
        val pendingTemplate = screen.onGetTemplate() as SectionedItemTemplate
        template.sections.zip(pendingTemplate.sections).forEach { (old, current) ->
            assertSame(old, current)
            assertSame(old.itemsDelegate, current.itemsDelegate)
            assertEquals(old.itemsDelegate.hashCode(), current.itemsDelegate.hashCode())
        }
        before.last().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, bridge.commands.size)
        assertEquals(1, toasts().size)
        shadowOf(Looper.getMainLooper()).idleFor(250, TimeUnit.MILLISECONDS)
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertSame(template, screen.onGetTemplate())
        shadowOf(Looper.getMainLooper()).idleFor(750, TimeUnit.MILLISECONDS)
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertSame(template, screen.onGetTemplate())
        assertSame(clickBinder(before.last().onClickDelegate), clickBinder(dashboardItems(screen).last().onClickDelegate))
        assertEquals(SectionedItemTemplate.SCROLL_STATE_PRESERVE_INDEX,
            (screen.onGetTemplate() as SectionedItemTemplate).scrollStatePersistenceStrategy)
    }

    @Test fun progressUsesTheSnapshotLanguageWithoutRefreshingTheGrid() {
        modernHost()
        bridge.response.put("strings", JSONObject().put("working", "Отправка…"))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val original = screen.onGetTemplate()
        val submissions = lifecycle.templatesReturned.size
        dashboardItems(screen).first().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idleFor(2, TimeUnit.SECONDS)
        assertEquals(listOf("Gate · Отправка…"), toasts())
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertSame(original, screen.onGetTemplate())
    }

    @Test fun rejectedCommandsShowFeedbackAndRemainRetryableWithoutGridRefresh() {
        modernHost()
        bridge.commandOutcome = "offline"
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val original = screen.onGetTemplate()
        val submissions = lifecycle.templatesReturned.size
        val click = dashboardItems(screen).first().onClickDelegate!!
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(2, toasts().size)
        assertEquals(context.getString(R.string.car_unreachable), toasts().last())
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertSame(original, screen.onGetTemplate())
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(2, bridge.commands.size)
        assertEquals(4, toasts().size)
        assertEquals(submissions, lifecycle.templatesReturned.size)
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

    @Test fun switchProgressDoesNotRefreshUntilFreshStateChangesItsIcon() {
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
        val submissions = lifecycle.templatesReturned.size
        val click = dashboardItems(screen).last().onClickDelegate!!
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("OFF", bridge.commands.single()["actionId"])
        assertEquals(listOf("Light · Sending…"), toasts())
        assertSame(original, screen.onGetTemplate())
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertSame(clickBinder(click), clickBinder(dashboardItems(screen).last().onClickDelegate))
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, bridge.commands.size)
        control.put("state", "OFF")
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertEquals(submissions + 1, lifecycle.templatesReturned.size)
        val updated = screen.onGetTemplate() as SectionedItemTemplate
        assertSame(original.sections.first(), updated.sections.first())
        assertEquals(R.drawable.car_off, dashboardItems(screen).last().image!!.icon!!.resId)
        assertSame(clickBinder(click), clickBinder(dashboardItems(screen).last().onClickDelegate))
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("OFF", "ON"), bridge.commands.map { it["actionId"] })
    }

    @Test fun localAndBackendPendingLeaveThePressedSectionUnchanged() {
        modernHost()
        bridge.commandWaitForFeedback = true
        bridge.delayCommandReply = true
        val control = bridge.response.getJSONArray("controls").getJSONObject(0)
            .put("waitForFeedback", true)
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val original = screen.onGetTemplate()
        val submissions = lifecycle.templatesReturned.size
        val click = dashboardItems(screen).first().onClickDelegate!!
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertSame(original, screen.onGetTemplate())
        bridge.commandReplies.removeAt(0)()
        shadowOf(Looper.getMainLooper()).idle()
        assertSame(original, screen.onGetTemplate())
        shadowOf(Looper.getMainLooper()).idleFor(2, TimeUnit.SECONDS)
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertSame(original, screen.onGetTemplate())
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, bridge.commands.size)
        assertEquals(1, toasts().size)
        control.put("pending", JSONObject.NULL).put("state", "OPEN")
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertEquals(submissions + 1, lifecycle.templatesReturned.size)
        assertEquals(CarColor.GREEN, dashboardItems(screen).first().image!!.tint)
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
        val lifecycle = start(screen)
        val original = screen.onGetTemplate()
        val submissions = lifecycle.templatesReturned.size
        val click = dashboardItems(screen).first().onClickDelegate!!
        bridge.response = JSONObject().put("outcome", "unreachable")
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertSame(original, screen.onGetTemplate())
        assertEquals(listOf("Enter", "Exit"), dashboardItems(screen).map { it.title.toString() })
        assertEquals(listOf(context.getString(R.string.car_reconnecting)), toasts())
        shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS)
        assertEquals(1, toasts().size)
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(bridge.commands.isEmpty())
        assertEquals(2, toasts().size)
        bridge.response = FakeBridge.snapshot()
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertSame(original, screen.onGetTemplate())
        assertEquals(submissions, lifecycle.templatesReturned.size)
        click.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("OPEN", bridge.commands.single()["actionId"])
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
        assertSame(clickBinder(click), clickBinder(dashboardItems(screen).single().onClickDelegate))
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
        assertSame(clickBinder(original.onClickDelegate), clickBinder(dashboardItems(screen).single().onClickDelegate))
        assertEquals(original.text, dashboardItems(screen).single().text)
        assertEquals(1, toasts().size)
        bridge.response.put("connected", true)
        val control = bridge.response.getJSONArray("controls").getJSONObject(0).put("failed", true)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertTrue(dashboardItems(screen).single().text.toString().contains("Not confirmed"))
        control.put("failed", false)
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        val recovered = dashboardItems(screen).single()
        assertEquals("", recovered.text.toString())
        assertSame(clickBinder(original.onClickDelegate), clickBinder(recovered.onClickDelegate))
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
        assertFalse(sending(dashboardItems(screen)[1]))
        assertEquals(1, toasts().size)
        assertFalse(sending(dashboardItems(screen)[2]))
    }

    @Test fun commandGuardsHaveIndependentOneSecondTimersWithoutGridUpdates() {
        modernHost()
        val a = commandButton("A").put("pending", "PRESS")
        val b = commandButton("B")
        bridge.response.put("controls", JSONArray().put(a).put(b))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val original = screen.onGetTemplate()
        val submissions = lifecycle.templatesReturned.size
        val clicks = dashboardItems(screen).map { it.onClickDelegate!! }
        clicks[0].sendClick(done)
        shadowOf(Looper.getMainLooper()).idleFor(100, TimeUnit.MILLISECONDS)
        clicks[1].sendClick(done)
        shadowOf(Looper.getMainLooper()).idleFor(899, TimeUnit.MILLISECONDS)
        clicks.forEach { it.sendClick(done) }
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("A", "B"), bridge.commands.map { it["controlId"] })
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.MILLISECONDS)
        clicks.forEach { it.sendClick(done) }
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("A", "B", "A"), bridge.commands.map { it["controlId"] })
        shadowOf(Looper.getMainLooper()).idleFor(100, TimeUnit.MILLISECONDS)
        clicks[1].sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("A", "B", "A", "B"), bridge.commands.map { it["controlId"] })
        assertEquals(4, toasts().size)
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertSame(original, screen.onGetTemplate())
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

    @Test fun modernDashboardResumeClearsCommandGuardsAndIgnoresOldCallbacks() {
        modernHost()
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        dashboardItems(screen).first().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse(sending(dashboardItems(screen).first()))
        assertEquals(1, toasts().size)
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

    @Test fun modernDisconnectedDashboardUsesPopupAndRejectsClickableActions() {
        modernHost()
        bridge.response = FakeBridge.snapshot(false)
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        start(screen)
        val items = dashboardItems(screen)
        assertTrue(items.all { it.onClickDelegate != null && it.text.toString() == "Gate" })
        assertEquals(listOf(context.getString(R.string.car_reconnecting)), toasts())
        items.first().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(bridge.commands.isEmpty())
        assertEquals(2, toasts().size)
    }

    @Test fun brokerAndNetworkOutagesAnnounceOncePerEpisodeWithoutReplacingControls() {
        modernHost()
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val original = screen.onGetTemplate()
        val captions = dashboardItems(screen).map { it.text.toString() }
        val submissions = lifecycle.templatesReturned.size
        bridge.response.put("connected", false).put("status", "error")
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertEquals(1, toasts().size)
        bridge.response.put("status", "reconnecting")
        shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS)
        assertEquals(1, toasts().size)
        assertEquals(captions, dashboardItems(screen).map { it.text.toString() })
        assertSame(original, screen.onGetTemplate())
        bridge.response.put("connected", true).put("status", "connected")
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        bridge.response.put("connected", false).put("status", "reconnecting")
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        assertEquals(2, toasts().size)
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertSame(original, screen.onGetTemplate())
    }

    @Test fun reconnectPopupUsesTheSnapshotLocaleAndReturnsWhenScreenResumesOffline() {
        modernHost()
        bridge.response = FakeBridge.snapshot(false)
            .put("strings", JSONObject().put("reconnecting", "Переподключение…"))
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        assertEquals(listOf("Переподключение…"), toasts())
        shadowOf(Looper.getMainLooper()).idleFor(2, TimeUnit.SECONDS)
        assertEquals(1, toasts().size)
        lifecycle.moveToState(Lifecycle.State.CREATED)
        lifecycle.moveToState(Lifecycle.State.RESUMED)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("Переподключение…", "Переподключение…"), toasts())
        assertTrue(dashboardItems(screen).all { it.text.toString() == "Gate" })
    }

    @Test fun manualReconnectShowsProgressBeforeTheBridgeReplies() {
        modernHost()
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val original = screen.onGetTemplate() as SectionedItemTemplate
        val submissions = lifecycle.templatesReturned.size
        bridge.delayed = true
        original.header!!.endHeaderActions.single().onClickDelegate!!.sendClick(done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf(context.getString(R.string.car_reconnecting)), toasts())
        assertSame(original, screen.onGetTemplate())
        bridge.callbacks.removeAt(0)(JSONObject())
        bridge.callbacks.removeAt(0)(FakeBridge.snapshot(false))
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, toasts().size)
        assertEquals(submissions, lifecycle.templatesReturned.size)
        assertTrue(bridge.commands.isEmpty())
    }

    @Test fun phoneStateChangesRefreshOnceWithScrollPreservationAndViewportReporting() {
        modernHost()
        val controls = JSONArray()
        repeat(40) { index -> controls.put(commandButton("Light $index").put("kind", "switch")
            .put("waitForFeedback", true).put("state", "OFF").put("actions", JSONArray()
                .put(JSONObject().put("id", "ON").put("title", "On").put("icon", "on"))
                .put(JSONObject().put("id", "OFF").put("title", "Off").put("icon", "off")))) }
        bridge.response.put("controls", controls)
        val screen = DashboardControlsCarScreen(context, bridge, "d")
        val lifecycle = start(screen)
        val original = screen.onGetTemplate() as SectionedItemTemplate
        val submissions = lifecycle.templatesReturned.size
        original.sections.single().onItemVisibilityChangedDelegate!!.sendItemVisibilityChanged(30, 38, done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(submissions, lifecycle.templatesReturned.size)
        // Model the user's reproduction: the phone publishes state; Auto has
        // received no tap and sends no command of its own.
        controls.getJSONObject(32).put("state", "ON")
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        val updated = screen.onGetTemplate() as SectionedItemTemplate
        assertEquals(submissions + 1, lifecycle.templatesReturned.size)
        assertEquals(SectionedItemTemplate.SCROLL_STATE_PRESERVE_INDEX, updated.scrollStatePersistenceStrategy)
        assertEquals(CarColor.GREEN, dashboardItems(screen)[32].image!!.tint)
        assertTrue(bridge.commands.isEmpty())
        updated.sections.single().onItemVisibilityChangedDelegate!!.sendItemVisibilityChanged(0, 8, done)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(submissions + 1, lifecycle.templatesReturned.size)
        // Client/IPC tests cannot assert where Android Auto's actual renderer
        // scrolled. Visibility callbacks provide that evidence on the car.
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

    @Test fun disconnectedActionsShowOneReconnectingPopupAndCannotSend() {
        bridge.response = FakeBridge.snapshot(false)
        val screen = ActionsCarScreen(context, bridge, "d", "gate")
        start(screen)
        assertTrue(actions(screen).all { it.onClickDelegate == null && it.text == null })
        assertEquals(listOf(context.getString(R.string.car_reconnecting)), toasts())
        shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS)
        assertEquals(1, toasts().size)
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
