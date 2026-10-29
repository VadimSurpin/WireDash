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
    private val sending = mutableMapOf<String, Sending>()
    private val sections = mutableMapOf<String, CachedSection>()
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
                        button(current, control, target, appearance, control.getString("name"), null))
                } else for (action in actions) {
                    items.add(button(current, control, action, action, action.getString("title"),
                        if (control.optString("kind") in setOf("cover", "options")) control.getString("name") else null))
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
        val built = template.build()
        val previous = previousTemplate
        if (previous != null && previous.header == built.header &&
            previous.sections.size == built.sections.size &&
            previous.sections.indices.all { previous.sections[it] === built.sections[it] }) return previous
        previousTemplate = built
        return built
    }

    private fun button(snapshot: JSONObject, control: JSONObject, target: JSONObject,
        appearance: JSONObject, title: String, subtitle: String?): GridItem {
        val controlId = control.getString("id")
        val actionId = target.getString("id")
        val switch = control.optString("kind") == "switch"
        // Ignore cached backend pending data for command-only tiles: their
        // spinner lasts exactly one second, even if the next poll is late.
        val pending = sending[controlId]?.action ?: if (control.optBoolean("waitForFeedback"))
            control.optString("pending").takeUnless { control.isNull("pending") } else null
        val loading = pending != null && (switch || pending == actionId)
        val connected = snapshot.optBoolean("connected")
        val item = GridItem.Builder().setTitle(title)
        // Let the host animate its loading indicator. Replacing the icon for
        // every animation frame replaces the lazy section's content repeatedly.
        if (loading) item.setLoading(true)
        else item.setImage(actionIcon(appearance, if (switch) control.optString("state") == "ON"
            else selected(control, appearance)), GridItem.IMAGE_TYPE_ICON)
        when {
            !connected -> item.setText(word("reconnecting", R.string.car_reconnecting))
            control.optBoolean("failed") -> item.setText(word("unconfirmed", R.string.car_unconfirmed))
            subtitle != null -> item.setText(subtitle)
        }
        if (connected && !loading) item.setOnClickListener { send(controlId, actionId) }
        return item.build()
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

    private fun send(controlId: String, actionId: String) {
        // Retained host click delegates must not repeat a busy command.
        val control = data?.optJSONArray("controls")?.objects()?.firstOrNull { it.optString("id") == controlId }
        val pending = sending[controlId]?.action ?: if (control?.optBoolean("waitForFeedback") == true)
            control.optString("pending").takeUnless { control.isNull("pending") } else null
        if (data?.optBoolean("connected") != true || pending == actionId ||
            (control?.optString("kind") == "switch" && pending != null)) return
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
