@file:Suppress("DEPRECATION") // API 6 hosts use the legacy header setters.

package pro.surpin.wiredash.car

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.CarToast
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import org.json.JSONArray
import org.json.JSONObject
import pro.surpin.wiredash.R
import pro.surpin.wiredash.ShortcutEngine

internal interface CarBridge {
    fun call(method: String, args: Map<String, Any> = emptyMap(), done: (JSONObject) -> Unit)
}

internal class EngineCarBridge(private val context: Context) : CarBridge {
    override fun call(method: String, args: Map<String, Any>, done: (JSONObject) -> Unit) {
        ShortcutEngine.car(context, method, args) { raw ->
            done(try { JSONObject(raw) } catch (_: Exception) { JSONObject().put("outcome", "error") })
        }
    }
}

internal fun JSONArray.objects(): List<JSONObject> =
    (0 until length()).mapNotNull { optJSONObject(it) }

/** Poll cached MQTT state only while visible; no poll ever sends a command. */
internal abstract class PollingCarScreen(
    context: CarContext,
    protected val bridge: CarBridge,
) : Screen(context) {
    protected val handler = Handler(Looper.getMainLooper())
    protected var data: JSONObject? = null
    protected var visible = false
    private var generation = 0
    private var fetching = false
    private val poll = Runnable { refresh() }
    protected abstract val method: String
    protected open val arguments: Map<String, Any> = emptyMap()

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) {
                visible = true
                generation++
                fetching = false
                data = null
                refresh()
            }
            override fun onStop(owner: LifecycleOwner) {
                visible = false
                generation++
                fetching = false
                handler.removeCallbacksAndMessages(null)
                onHidden()
            }
        })
    }

    protected fun refresh() {
        if (!visible || fetching) return
        handler.removeCallbacks(poll)
        fetching = true
        val request = generation
        bridge.call(method, arguments) { next ->
            if (!visible || generation != request) return@call
            fetching = false
            val changed = data?.toString() != next.toString()
            data = next
            if (onData() || changed) invalidate()
            handler.postDelayed(poll, 1_000)
        }
    }

    protected open fun onData(): Boolean = false
    protected open fun onHidden() {}
    protected fun word(key: String, fallback: Int): String =
        data?.optJSONObject("strings")?.optString(key)?.takeIf { it.isNotEmpty() }
            ?: carContext.getString(fallback)

    protected fun message(text: Int, root: Boolean = false): Template =
        MessageTemplate.Builder(carContext.getString(text))
            .setTitle("WireDash")
            .setHeaderAction(if (root) Action.APP_ICON else Action.BACK)
            .addAction(Action.Builder().setTitle(carContext.getString(R.string.car_retry))
                .setOnClickListener { refresh() }.build())
            .build()

    protected fun icon(name: String, selected: Boolean = false): CarIcon {
        val drawable = when (name) {
            "gateOpen" -> R.drawable.car_gate_open
            "gateClosed" -> R.drawable.car_gate_closed
            "gatePartial" -> R.drawable.car_gate_partial
            "rollerOpen" -> R.drawable.car_roller_open
            "rollerClosed" -> R.drawable.car_roller_closed
            "stop" -> R.drawable.car_stop
            "down" -> R.drawable.car_down
            "up" -> R.drawable.car_up
            "left" -> R.drawable.car_left
            "right" -> R.drawable.car_right
            "off" -> R.drawable.car_off
            "on" -> R.drawable.car_on
            else -> R.drawable.ic_shortcut_tile
        }
        val builder = CarIcon.Builder(IconCompat.createWithResource(carContext, drawable))
        if (selected) builder.setTint(CarColor.createCustom(0xff398500.toInt(), 0xffa9e34b.toInt()))
        return builder.build()
    }
}

/** Host limits are respected without silently losing dashboards or controls. */
internal abstract class PagedCarScreen(context: CarContext, bridge: CarBridge) :
    PollingCarScreen(context, bridge) {
    private var offset = 0
    protected fun list(title: String, root: Boolean, entries: List<JSONObject>,
        row: (JSONObject) -> Row): Template {
        val limit = carContext.getCarService(ConstraintManager::class.java)
            .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST).coerceAtLeast(3)
        val count = if (entries.size > limit) limit - 2 else limit
        if (offset >= entries.size) offset = 0
        val items = ItemList.Builder()
        if (offset > 0) items.addItem(Row.Builder()
            .setTitle(carContext.getString(R.string.car_previous))
            .setOnClickListener { offset = (offset - count).coerceAtLeast(0); invalidate() }.build())
        entries.drop(offset).take(count).forEach { items.addItem(row(it)) }
        if (offset + count < entries.size) items.addItem(Row.Builder()
            .setTitle(carContext.getString(R.string.car_next))
            .setOnClickListener { offset += count; invalidate() }.build())
        return ListTemplate.Builder().setTitle(title)
            .setHeaderAction(if (root) Action.APP_ICON else Action.BACK)
            .setSingleList(items.build()).build()
    }
}

internal class DashboardCarScreen(context: CarContext, bridge: CarBridge) : PagedCarScreen(context, bridge) {
    override val method = "carCatalog"
    override fun onGetTemplate(): Template {
        val current = data ?: return ListTemplate.Builder().setTitle("WireDash")
            .setHeaderAction(Action.APP_ICON).setLoading(true).build()
        if (current.has("outcome")) return message(R.string.car_error, true)
        val entries = current.optJSONArray("dashboards")?.objects().orEmpty()
        if (entries.isEmpty()) return message(R.string.car_setup, true)
        return list("WireDash", true, entries) { entry ->
            Row.Builder().setTitle(entry.getString("name")).addText(entry.getString("home"))
                .setBrowsable(true).setOnClickListener {
                    screenManager.push(ControlsCarScreen(carContext, bridge, entry.getString("id")))
                }.build()
        }
    }
}

internal class ControlsCarScreen(context: CarContext, bridge: CarBridge, private val dashboardId: String) :
    PagedCarScreen(context, bridge) {
    override val method = "carOpen"
    override val arguments get() = mapOf("dashboardId" to dashboardId)
    override fun onGetTemplate(): Template {
        val current = data ?: return ListTemplate.Builder().setTitle("WireDash")
            .setHeaderAction(Action.BACK).setLoading(true).build()
        if (current.has("outcome")) return message(if (current.optString("outcome") == "removed") R.string.car_removed else R.string.car_error)
        val entries = current.optJSONArray("controls")?.objects().orEmpty()
        if (entries.isEmpty()) return message(R.string.car_setup)
        return list(current.optString("name", "WireDash"), false, entries) { entry ->
            val row = Row.Builder().setTitle(entry.getString("name")).setBrowsable(true)
            if (!current.optBoolean("connected")) row.addText(word("reconnecting", R.string.car_reconnecting))
            else if (entry.optBoolean("waitForFeedback")) {
                val state = entry.optString("state").takeUnless { entry.isNull("state") }
                row.addText(when (state) {
                    "ON" -> current.optJSONObject("strings")?.optString("on") ?: "On"
                    "OFF" -> current.optJSONObject("strings")?.optString("off") ?: "Off"
                    "OPEN" -> current.optJSONObject("strings")?.optString("open") ?: "Open"
                    "CLOSE" -> current.optJSONObject("strings")?.optString("close") ?: "Close"
                    "STOP" -> current.optJSONObject("strings")?.optString("stop") ?: "Stop"
                    null -> carContext.getString(R.string.car_unknown)
                    else -> state
                })
            }
            row.setOnClickListener {
                screenManager.push(ActionsCarScreen(carContext, bridge, dashboardId, entry.getString("id")))
            }.build()
        }
    }
}

internal class ActionsCarScreen(context: CarContext, bridge: CarBridge,
    private val dashboardId: String, private val controlId: String) : PollingCarScreen(context, bridge) {
    override val method = "carOpen"
    override val arguments get() = mapOf("dashboardId" to dashboardId)
    private var working: String? = null
    private var sequence = 0
    private var clearOnSnapshot = false

    override fun onHidden() {
        sequence++
        working = null
        clearOnSnapshot = false
    }

    override fun onData(): Boolean {
        if (!clearOnSnapshot) return false
        clearOnSnapshot = false
        working = null
        return true
    }

    override fun onGetTemplate(): Template {
        val current = data ?: return GridTemplate.Builder().setTitle("WireDash")
            .setHeaderAction(Action.BACK).setLoading(true).build()
        if (current.has("outcome")) return message(if (current.optString("outcome") == "removed") R.string.car_removed else R.string.car_error)
        val control = current.optJSONArray("controls")?.objects()?.firstOrNull { it.optString("id") == controlId }
            ?: return message(R.string.car_removed)
        val items = ItemList.Builder()
        val connected = current.optBoolean("connected")
        for (action in control.getJSONArray("actions").objects()) {
            val id = action.getString("id")
            val pending = working == id || (!control.isNull("pending") && control.optString("pending") == id)
            val item = GridItem.Builder().setTitle(action.getString("title"))
            if (pending) item.setLoading(true)
            else item.setImage(icon(action.optString("icon"), control.optString("state") == id), GridItem.IMAGE_TYPE_ICON)
            if (!connected) item.setText(word("reconnecting", R.string.car_reconnecting))
            else if (control.optBoolean("failed")) item.setText(word("unconfirmed", R.string.car_unconfirmed))
            // The host forbids click listeners on loading GridItems. The
            // one-second command spinner then returns to a repeatable action.
            if (connected && !pending) item.setOnClickListener { send(id) }
            items.addItem(item.build())
        }
        return GridTemplate.Builder().setTitle(control.getString("name"))
            .setHeaderAction(Action.BACK).setSingleList(items.build())
            .setActionStrip(ActionStrip.Builder().addAction(Action.Builder()
                .setIcon(CarIcon.Builder(IconCompat.createWithResource(carContext, R.drawable.car_refresh)).build())
                .setOnClickListener { bridge.call("carReconnect") { refresh() } }.build()).build())
            .build()
    }

    private fun send(actionId: String) {
        val request = ++sequence
        working = actionId
        invalidate()
        bridge.call("carCommand", mapOf("dashboardId" to dashboardId,
            "controlId" to controlId, "actionId" to actionId,
            "expiresAt" to (System.currentTimeMillis() + 5_000))) { result ->
            if (!visible || request != sequence) return@call
            if (result.optString("outcome") != "sent") {
                working = null
                CarToast.makeText(carContext, carContext.getString(R.string.car_unreachable), CarToast.LENGTH_LONG).show()
                refresh()
                invalidate()
            } else if (result.optBoolean("waitForFeedback")) {
                clearOnSnapshot = true
                refresh()
            } else {
                handler.postDelayed({
                    if (visible && request == sequence) {
                        working = null
                        refresh()
                        invalidate()
                    }
                }, 1_000)
            }
        }
    }
}
