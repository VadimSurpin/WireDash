package pro.surpin.wiredash.car

import androidx.car.app.CarContext
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.Header
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.OnClickListener
import androidx.car.app.model.Row
import androidx.car.app.model.SectionedItemList
import androidx.car.app.model.Template
import androidx.car.app.model.Toggle
import org.json.JSONArray
import org.json.JSONObject
import pro.surpin.wiredash.R

/** Classic ListTemplate experiment: saved groups and two inline actions per row. */
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
    private data class CachedList(val rows: List<Row>, val list: ItemList)
    private val rows = mutableMapOf<RowKey, CachedRow>()
    private val actions = mutableMapOf<TileKey, CachedAction>()
    private val lists = mutableMapOf<String, CachedList>()
    private val navigationRows = mutableMapOf<String, Row>()
    private var previous: ListTemplate? = null
    private var previousGroups: List<Group> = emptyList()
    private var offset = 0
    private var pageSize = 1

    override fun buildTemplate(): Template {
        val current = data
        val header = Header.Builder().setTitle(current?.optString("name", "WireDash") ?: "WireDash")
            .setStartHeaderAction(Action.BACK).addEndHeaderAction(reconnectAction).build()
        val template = ListTemplate.Builder().setHeader(header)
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

        // Classic lists have host limits; never silently truncate saved actions.
        val limit = carContext.getCarService(ConstraintManager::class.java)
            .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST).coerceIn(3, 100)
        val total = groups.sumOf { it.rows.size }
        val count = if (total > limit) limit - 2 else limit
        pageSize = count
        if (offset >= total) offset = 0
        var cursor = 0
        val displayed = groups.mapNotNull { group ->
            val start = (offset - cursor).coerceAtLeast(0)
            val end = (offset + count - cursor).coerceIn(0, group.rows.size)
            cursor += group.rows.size
            if (start >= end) null else group.copy(rows = group.rows.subList(start, end))
        }.toMutableList()
        val navigation = mutableListOf<Row>()
        if (offset > 0) navigation.add(navigationRows.getOrPut("previous") {
            Row.Builder().setTitle(carContext.getString(R.string.car_previous)).setImage(icon("left"))
                .setOnClickListener { if (visible) { offset = (offset - pageSize).coerceAtLeast(0); invalidate() } }.build()
        })
        if (offset + count < total) navigation.add(navigationRows.getOrPut("next") {
            Row.Builder().setTitle(carContext.getString(R.string.car_next)).setImage(icon("right"))
                .setOnClickListener { if (visible) { offset += pageSize; invalidate() } }.build()
        })
        if (navigation.isNotEmpty()) displayed.add(Group("navigation/$offset", carContext.getString(R.string.car_controls), navigation))
        val activeLists = displayed.map { it.id }.toSet()
        lists.keys.retainAll(activeLists)
        for ((ordinal, group) in displayed.withIndex()) {
            val old = lists[group.id]
            val list = if (old != null && sameRows(old.rows, group.rows)) old.list else {
                val builder = ItemList.Builder().setOnItemsVisibilityChangedListener { first, last ->
                    if (visible) trace("list viewport section=$ordinal first=$first endExclusive=$last")
                }
                group.rows.forEach(builder::addItem)
                builder.build().also { lists[group.id] = CachedList(group.rows, it) }
            }
            template.addSectionedList(SectionedItemList.create(list, group.title))
        }
        val built = template.build()
        val old = previous
        if (old != null && old.header == built.header && previousGroups.size == displayed.size &&
            displayed.indices.all { i -> previousGroups[i].id == displayed[i].id &&
                previousGroups[i].title == displayed[i].title && sameRows(previousGroups[i].rows, displayed[i].rows) }) return old
        previous = built
        previousGroups = displayed
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
