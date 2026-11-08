package pro.surpin.wiredash.car

import androidx.car.app.CarContext
import androidx.car.app.model.Action
import androidx.car.app.model.Header
import androidx.car.app.model.Row
import androidx.car.app.model.RowSection
import androidx.car.app.model.SectionedItemTemplate
import androidx.car.app.model.Template
import org.json.JSONArray
import org.json.JSONObject
import pro.surpin.wiredash.R

/** Navigation only: MQTT state changes must not replace the scrolling group list. */
internal class DashboardGroupsCarScreen(
    context: CarContext,
    bridge: CarBridge,
    private val dashboardId: String,
) : PollingCarScreen(context, bridge) {
    override val method = "carOpen"
    override val arguments get() = mapOf("dashboardId" to dashboardId)

    private data class Group(val id: String, val title: String)
    private var displayedStructure: String? = null
    private var displayedTemplate: Template? = null

    private fun groups(snapshot: JSONObject): List<Group> {
        val controls = snapshot.optJSONArray("controls")?.objects().orEmpty()
        val sections = snapshot.optJSONArray("sections")?.objects().orEmpty()
        val known = sections.map { it.optString("id") }.toSet()
        val result = mutableListOf<Group>()
        if (controls.any { it.optString("sectionId") !in known })
            result.add(Group("unsectioned", carContext.getString(R.string.car_controls)))
        for (section in sections) {
            val id = section.optString("id")
            if (controls.any { it.optString("sectionId") == id })
                result.add(Group("group/$id", section.optString("name")))
        }
        return result
    }

    private fun structure(snapshot: JSONObject): String {
        if (snapshot.has("outcome")) return "error/" + snapshot.optString("outcome")
        // Include membership so deleting the last control removes its group.
        // Deliberately exclude states, positions, pending requests and failures.
        return JSONArray().put(snapshot.optString("name"))
            .put(JSONArray(groups(snapshot).map { group ->
                JSONArray().put(group.id).put(group.title)
            })).toString()
    }

    override fun stateUpdateStructure(): String? = data?.let(::structure)

    override fun onSnapshotChanged() {
        if (data?.let(::structure) != displayedStructure) invalidate()
    }

    override fun onGetTemplate(): Template {
        val current = data
        val key = current?.let(::structure)
        if (key == displayedStructure) displayedTemplate?.let { return it }
        val template = if (current == null) {
            SectionedItemTemplate.Builder().setHeader(Header.Builder().setTitle("WireDash")
                .setStartHeaderAction(Action.BACK).build()).setLoading(true).build()
        } else if (current.has("outcome")) {
            message(if (current.optString("outcome") == "removed") R.string.car_removed else R.string.car_error)
        } else {
            val entries = groups(current)
            if (entries.isEmpty()) message(R.string.car_setup) else {
                val rows = entries.map { group ->
                    Row.Builder().setTitle(group.title).setBrowsable(true)
                        .setOnClickListener {
                            screenManager.push(DashboardControlsCarScreen(
                                carContext, bridge, dashboardId, group.id))
                        }.build()
                }
                SectionedItemTemplate.Builder()
                    .setHeader(Header.Builder().setTitle(current.optString("name", "WireDash"))
                        .setStartHeaderAction(Action.BACK).build())
                    .setScrollStatePersistenceStrategy(SectionedItemTemplate.SCROLL_STATE_PRESERVE_INDEX)
                    .addSection(RowSection.Builder().setItems(rows).build()).build()
            }
        }
        displayedStructure = key
        displayedTemplate = template
        return template
    }
}
