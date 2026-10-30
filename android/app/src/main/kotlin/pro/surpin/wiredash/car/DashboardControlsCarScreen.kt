package pro.surpin.wiredash.car

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridSection
import androidx.car.app.model.Header
import androidx.car.app.model.SectionedItemTemplate
import androidx.car.app.model.Template
import androidx.core.graphics.drawable.IconCompat
import org.json.JSONArray
import org.json.JSONObject
import pro.surpin.wiredash.R

/** Saved dashboard groups, with immediately usable buttons in one scrolling screen. */
internal class DashboardControlsCarScreen(
    context: CarContext,
    bridge: CarBridge,
    private val dashboardId: String,
) : PollingCarScreen(context, bridge) {
    override val method = "carOpen"
    override val arguments get() = mapOf("dashboardId" to dashboardId)

    private class Sending(val action: String, var awaitingSnapshot: Boolean = false)
    private class CachedSection(val title: String?, val commands: List<String>,
        val items: List<GridItem>, val section: GridSection)
    private data class TileKey(val controlId: String, val kind: String, val actionId: String?)
    private class CachedTile(val online: GridItem.Builder) {
        val offline = GridItem.Builder()
        var item: GridItem? = null
        var appearance: String? = null
    }
    private val sending = mutableMapOf<String, Sending>()
    private val sections = mutableMapOf<String, CachedSection>()
    private val tiles = mutableMapOf<TileKey, CachedTile>()
    private val busyIcon by lazy {
        CarIcon.Builder(IconCompat.createWithResource(carContext, R.drawable.car_sending_0)).build()
    }
    private var previousTemplate: SectionedItemTemplate? = null
    private var presentedTemplate: Template? = null
    private var renderScheduled = false
    private val reconnectAction by lazy {
        Action.Builder().setIcon(icon("refresh"))
            .setOnClickListener { bridge.call("carReconnect") { refresh() } }.build()
    }
    private val materialIcons = mutableMapOf<Int, Bitmap>()
    private val materialFont by lazy {
        try { Typeface.createFromAsset(carContext.assets, "flutter_assets/fonts/MaterialIcons-Regular.otf") }
        catch (_: Exception) { null }
    }

    override fun onHidden() {
        sending.clear()
        renderScheduled = false
    }

    override fun onSnapshotChanged() = render()

    private fun render() {
        if (renderScheduled || !visible) return
        renderScheduled = true
        handler.post {
            renderScheduled = false
            if (visible && buildTemplate() !== presentedTemplate) invalidate()
        }
    }

    override fun onData(): Boolean {
        val confirmed = sending.filterValues { it.awaitingSnapshot }.keys
        confirmed.forEach { sending.remove(it) }
        return confirmed.isNotEmpty()
    }

    override fun onGetTemplate(): Template = buildTemplate().also { presentedTemplate = it }

    private fun buildTemplate(): Template {
        val current = data
        val header = Header.Builder().setTitle(current?.optString("name", "WireDash") ?: "WireDash")
            .setStartHeaderAction(Action.BACK)
            .addEndHeaderAction(reconnectAction).build()
        val template = SectionedItemTemplate.Builder().setHeader(header)
            .setScrollStatePersistenceStrategy(SectionedItemTemplate.SCROLL_STATE_PRESERVE_INDEX)
        if (current == null) return template.setLoading(true).build()
        if (current.has("outcome")) return message(if (current.optString("outcome") == "removed") R.string.car_removed else R.string.car_error)
        val controls = current.optJSONArray("controls")?.objects().orEmpty()
        if (controls.isEmpty()) return message(R.string.car_setup)

        val activeSections = mutableSetOf<String>()
        val activeTiles = mutableSetOf<TileKey>()
        fun addGroup(id: String, title: String?, entries: List<JSONObject>) {
            if (entries.isEmpty()) return
            activeSections.add(id)
            val items = mutableListOf<GridItem>()
            for (control in entries) {
                val actions = control.getJSONArray("actions").objects()
                if (control.optString("kind") == "switch") {
                    // A switch is one tile, as on the phone. Its current icon
                    // reflects feedback; tapping sends the opposite value.
                    val on = control.optString("state") == "ON"
                    val appearance = actions.firstOrNull { it.optString("id") == if (on) "ON" else "OFF" }
                    val target = actions.firstOrNull { it.optString("id") == if (on) "OFF" else "ON" }
                    if (appearance != null && target != null) items.add(
                        button(current, control, target, appearance, control.getString("name"), null, activeTiles))
                } else for (action in actions) {
                    items.add(button(current, control, action, action, action.getString("title"),
                        if (control.optString("kind") in setOf("cover", "options")) control.getString("name") else null, activeTiles))
                }
            }
            // Compare rendered content rather than raw MQTT snapshots: a
            // local spinner handed over to backend pending, or an intermediate
            // position with no matching preset, must not replace a lazy list.
            // Include action metadata because CarIcon doesn't compare bitmap
            // pixels, and an identical-looking tile may have a new command ID.
            val commands = entries.map { JSONArray().put(it.getString("id"))
                .put(it.optString("kind")).put(it.getJSONArray("actions")).toString() }
            val cached = sections[id]
            if (cached != null && cached.title == title && cached.commands == commands && cached.items == items) {
                template.addSection(cached.section)
                return
            }
            val section = GridSection.Builder().setItems(items)
            if (!title.isNullOrBlank()) section.setTitle(title)
            val built = section.build()
            sections[id] = CachedSection(title, commands, items, built)
            template.addSection(built)
        }

        val groups = current.optJSONArray("sections")?.objects().orEmpty()
        val known = groups.map { it.getString("id") }.toSet()
        addGroup("unsectioned", null, controls.filter { it.optString("sectionId") !in known })
        for (section in groups) addGroup("group/" + section.getString("id"), section.getString("name"),
            controls.filter { it.optString("sectionId") == section.getString("id") })
        sections.keys.retainAll(activeSections)
        tiles.keys.retainAll(activeTiles)
        val built = template.build()
        val previous = previousTemplate
        if (previous != null && previous.header == built.header &&
            previous.sections.size == built.sections.size &&
            previous.sections.indices.all { previous.sections[it] === built.sections[it] }) return previous
        previousTemplate = built
        return built
    }

    private fun button(snapshot: JSONObject, control: JSONObject, target: JSONObject,
        appearance: JSONObject, title: String, subtitle: String?, activeTiles: MutableSet<TileKey>): GridItem {
        val controlId = control.getString("id")
        val actionId = target.getString("id")
        val switch = control.optString("kind") == "switch"
        // Ignore cached backend pending data for command-only tiles: their
        // spinner lasts exactly one second, even if the next poll is late.
        val pending = sending[controlId]?.action ?: if (control.optBoolean("waitForFeedback"))
            control.optString("pending").takeUnless { control.isNull("pending") } else null
        val loading = pending != null && (switch || pending == actionId)
        val connected = snapshot.optBoolean("connected")
        // A switch keeps one identity across ON/OFF. Its listener reads the
        // latest snapshot instead of retaining the target from an older tile.
        val key = TileKey(controlId, control.getString("kind"), if (switch) null else actionId)
        activeTiles.add(key)
        val tile = tiles.getOrPut(key) {
            CachedTile(GridItem.Builder().setOnClickListener { send(key) })
        }
        val item = (if (connected) tile.online else tile.offline).setTitle(title)
        // Native loading tiles remove their image and click delegate. Keep a
        // focusable image tile throughout the command, including the *same*
        // Binder click delegate. A static busy icon needs no animation redraws.
        item.setImage(if (loading) busyIcon else actionIcon(appearance,
            if (switch) control.optString("state") == "ON" else selected(control, appearance)),
            GridItem.IMAGE_TYPE_ICON)
        // Builders are reused: explicitly clear old reconnect/error text.
        item.setText(when {
            !connected -> word("reconnecting", R.string.car_reconnecting)
            control.optBoolean("failed") -> word("unconfirmed", R.string.car_unconfirmed)
            else -> subtitle.orEmpty()
        })
        val built = item.build()
        val metadata = appearance.toString()
        val previous = tile.item
        if (previous != null && previous == built && tile.appearance == metadata) return previous
        tile.item = built
        tile.appearance = metadata
        return built
    }

    private fun actionIcon(action: JSONObject, selected: Boolean): CarIcon {
        val codepoint = action.optInt("iconCodepoint")
        val font = materialFont
        val icon = if (codepoint == 0 || font == null || !Character.isValidCodePoint(codepoint)) {
            CarIcon.Builder(icon(action.optString("icon"), selected))
        } else {
            val bitmap = materialIcons.getOrPut(codepoint) {
                val result = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888)
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    typeface = font; textSize = 104f; color = Color.WHITE; textAlign = Paint.Align.CENTER
                }
                Canvas(result).drawText(String(Character.toChars(codepoint)), 64f,
                    64f - (paint.ascent() + paint.descent()) / 2, paint)
                result
            }
            CarIcon.Builder(IconCompat.createWithBitmap(bitmap))
        }
        if (selected) icon.setTint(CarColor.GREEN)
        else if (action.has("colorArgb")) {
            val color = action.getLong("colorArgb").toInt()
            icon.setTint(CarColor.createCustom(color, color))
        }
        return icon.build()
    }

    private fun send(key: TileKey) {
        // Stable host delegates use current state and cannot invoke a hidden,
        // removed, repurposed, offline or busy control.
        if (!visible || data?.optBoolean("connected") != true) return
        val controlId = key.controlId
        val control = data?.optJSONArray("controls")?.objects()?.firstOrNull { it.optString("id") == controlId }
            ?: return
        if (control.optString("kind") != key.kind) return
        val actionId = key.actionId ?: if (control.optString("state") == "ON") "OFF" else "ON"
        if (control.getJSONArray("actions").objects().none { it.optString("id") == actionId }) return
        val pending = sending[controlId]?.action ?: if (control.optBoolean("waitForFeedback"))
            control.optString("pending").takeUnless { control.isNull("pending") } else null
        if (pending == actionId || (key.kind == "switch" && pending != null)) return
        val request = Sending(actionId)
        sending[controlId] = request
        render()
        bridge.call("carCommand", mapOf("dashboardId" to dashboardId,
            "controlId" to controlId, "actionId" to actionId,
            "expiresAt" to (System.currentTimeMillis() + 5_000))) { result ->
            if (!visible || sending[controlId] !== request) return@call
            if (result.optString("outcome") != "sent") {
                sending.remove(controlId)
                CarToast.makeText(carContext, carContext.getString(R.string.car_unreachable), CarToast.LENGTH_LONG).show()
                refresh()
                render()
            } else if (result.optBoolean("waitForFeedback")) {
                request.awaitingSnapshot = true
                refresh()
            } else handler.postDelayed({
                if (visible && sending[controlId] === request) {
                    sending.remove(controlId)
                    refresh()
                    render()
                }
            }, 1_000)
        }
    }
}
