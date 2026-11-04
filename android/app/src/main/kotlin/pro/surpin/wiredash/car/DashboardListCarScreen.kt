package pro.surpin.wiredash.car

import androidx.car.app.CarContext
import androidx.car.app.model.Action
import androidx.car.app.model.Header
import androidx.car.app.model.OnClickListener
import androidx.car.app.model.Row
import androidx.car.app.model.RowSection
import androidx.car.app.model.SectionedItemTemplate
import androidx.car.app.model.Template
import androidx.car.app.model.Toggle
import org.json.JSONArray
import org.json.JSONObject
import pro.surpin.wiredash.R

/** Saved groups in a scrolling list, with two inline actions per row and no page controls. */
internal class DashboardListCarScreen(context: CarContext, bridge: CarBridge, dashboardId: String) :
    DashboardControlsCarScreen(context, bridge, dashboardId) {
    private data class RowKey(val control: String, val kind: String, val actions: List<String>)
    private class CachedRow(val click: OnClickListener?, val toggle: Toggle.Builder?) {
        var configuration: String? = null
        var row: Row? = null
    }
    private class CachedAction(val builder: Action.Builder) {
        var metadata: String? = null
        var action: Action? = null
    }
    private data class Group(val id: String, val title: String, val rows: List<Row>)
    private data class CachedRows(val group: Group, val section: RowSection)
    private val rows = mutableMapOf<RowKey, CachedRow>()
    private val actions = mutableMapOf<TileKey, CachedAction>()
    private val rowSections = mutableMapOf<String, CachedRows>()
    private var previous: SectionedItemTemplate? = null
    private var previousGroups: List<Group> = emptyList()

    override fun buildTemplate(): Template {
        val current = data
        val header = Header.Builder().setTitle(current?.optString("name", "WireDash") ?: "WireDash")
            .setStartHeaderAction(Action.BACK).addEndHeaderAction(reconnectAction).build()
        val template = SectionedItemTemplate.Builder().setHeader(header)
            .setScrollStatePersistenceStrategy(SectionedItemTemplate.SCROLL_STATE_PRESERVE_INDEX)
        if (current == null) return template.setLoading(true).build()
        if (current.has("outcome")) return message(if (current.optString("outcome") == "removed") R.string.car_removed else R.string.car_error)
        val controls = current.optJSONArray("controls")?.objects().orEmpty()
        if (controls.isEmpty()) return message(R.string.car_setup)
        val activeRows = mutableSetOf<RowKey>()
        val activeActions = mutableSetOf<TileKey>()
        val groups = mutableListOf<Group>()
        fun addGroup(id: String, title: String, entries: List<JSONObject>) {
            val content = entries.flatMap { control ->
                val all = control.getJSONArray("actions").objects()
                if (all.isEmpty()) emptyList() else {
                    val kind = control.getString("kind")
                    val chunks = when (kind) {
                        "switch", "button", "video" -> listOf(all)
                        "cover" -> {
                            val directions = all.filter { it.getString("id") in setOf("OPEN", "CLOSE") }
                            if (directions.size == 2) listOf(directions) + all.filter { it !in directions }.chunked(2)
                            else all.chunked(2)
                        }
                        else -> all.chunked(2)
                    }
                    chunks.map { chunk -> row(current, control, chunk, activeRows, activeActions) }
                }
            }
            if (content.isNotEmpty()) groups.add(Group(id, title, content))
        }
        val sections = current.optJSONArray("sections")?.objects().orEmpty()
        val known = sections.map { it.getString("id") }.toSet()
        addGroup("unsectioned", carContext.getString(R.string.car_controls),
            controls.filter { it.optString("sectionId") !in known })
        for (section in sections) addGroup("group/" + section.getString("id"), section.getString("name"),
            controls.filter { it.optString("sectionId") == section.getString("id") })
        rows.keys.retainAll(activeRows)
        actions.keys.retainAll(activeActions)

        // RowSection serves item ranges as the host scrolls. Unlike a classic
        // ListTemplate, it does not truncate a dashboard at the host list limit
        // or at the classic template's 100-row serialization limit.
        rowSections.keys.retainAll(groups.map { it.id }.toSet())
        for (group in groups) {
            val old = rowSections[group.id]
            val section = if (old != null && old.group.title == group.title &&
                sameRows(old.group.rows, group.rows)) old.section else {
                RowSection.Builder().setTitle(group.title).setItems(group.rows).build()
                    .also { rowSections[group.id] = CachedRows(group, it) }
            }
            template.addSection(section)
        }
        val built = template.build()
        val old = previous
        if (old != null && old.header == built.header && previousGroups.size == groups.size &&
            groups.indices.all { i -> previousGroups[i].id == groups[i].id &&
                previousGroups[i].title == groups[i].title && sameRows(previousGroups[i].rows, groups[i].rows) }) return old
        previous = built
        previousGroups = groups
        return built
    }

    private fun sameRows(a: List<Row>, b: List<Row>) = a.size == b.size && a.indices.all { a[it] === b[it] }

    private fun row(snapshot: JSONObject, control: JSONObject, entries: List<JSONObject>,
        activeRows: MutableSet<RowKey>, activeActions: MutableSet<TileKey>): Row {
        val id = control.getString("id")
        val kind = control.getString("kind")
        val key = RowKey(id, kind, if (kind == "switch") emptyList() else entries.map { it.getString("id") })
        activeRows.add(key)
        if (kind !in setOf("switch", "button", "video")) entries.forEach {
            activeActions.add(TileKey(id, kind, it.getString("id")))
        }
        val cached = rows.getOrPut(key) {
            val toggle = if (kind == "switch") Toggle.Builder { checked ->
                val target = if (checked) "ON" else "OFF"
                val latest = data?.optJSONArray("controls")?.objects()?.firstOrNull { it.optString("id") == id }
                if (latest?.optString("state") != target) send(TileKey(id, kind, target))
            } else null
            val click = if (kind == "video" || kind == "button" || (kind != "switch" && entries.size == 1))
                OnClickListener { send(TileKey(id, kind, entries.first().getString("id"))) } else null
            CachedRow(click, toggle)
        }
        val configuration = JSONArray().put(control.getString("name"))
            .put(control.getJSONArray("actions")).put(control.optBoolean("waitForFeedback")).toString()
        val old = cached.row
        val previousConfiguration = cached.configuration
        if (!snapshot.optBoolean("connected") && kind != "video" && old != null && cached.configuration == configuration) return old
        // Rebuild content without accumulating old text/actions. Equal rows
        // retain their previous model and host delegate after comparison below.
        val content = Row.Builder().setTitle(control.getString("name"))
        cached.click?.let { content.setOnClickListener(it) }
        if (kind == "video") content.setBrowsable(true)
        if (kind == "switch") {
            val on = control.optString("state") == "ON"
            val appearance = control.getJSONArray("actions").objects().first { it.getString("id") == if (on) "ON" else "OFF" }
            content.setImage(actionIcon(appearance, on)).setToggle(cached.toggle!!.setChecked(on).build())
            if (control.isNull("state")) content.addText(carContext.getString(R.string.car_unknown))
        } else if (kind == "video") {
            content.setImage(actionIcon(entries.first(), false)).addText(carContext.getString(R.string.car_video_phone))
        } else if (kind == "button") {
            content.setImage(actionIcon(entries.first(), selected(control, entries.first())))
        } else {
            for (entry in entries) {
                val actionKey = TileKey(id, kind, entry.getString("id"))
                val action = actions.getOrPut(actionKey) { CachedAction(Action.Builder().setOnClickListener { send(actionKey) }) }
                val rendered = action.builder.setTitle(entry.getString("title"))
                    .setIcon(actionIcon(entry, selected(control, entry))).build()
                val metadata = entry.toString()
                val retained = if (action.action == rendered && action.metadata == metadata) action.action!! else rendered
                action.action = retained
                action.metadata = metadata
                content.addAction(retained)
            }
            content.addText(entries.joinToString(" · ") { it.getString("title") })
        }
        if (control.optBoolean("waitForFeedback") && control.optBoolean("failed")) {
            content.addText(word("unconfirmed", R.string.car_unconfirmed))
        }
        val built = content.build()
        cached.configuration = configuration
        if (old != null && old == built && configuration == previousConfiguration) return old
        cached.row = built
        return built
    }
}
