package pro.surpin.wiredash

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.app.ActivityManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/**
 * Debug builds only: drives the shortcut engine from adb.
 *   adb shell am broadcast -n pro.surpin.wiredash/.ShortcutDebugReceiver \
 *     --es cmd toggle --es home <connectionId> --es ieee <0x...>
 *   ... --es cmd scene --es home <connectionId> --es scene <sceneId>
 */
class ShortcutDebugReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val tap = System.currentTimeMillis()
        val pending = goAsync()
        val cmd = intent.getStringExtra("cmd")
        if (cmd == "carExitInfo") {
            val exits = if (Build.VERSION.SDK_INT >= 30)
                ctx.getSystemService(ActivityManager::class.java).getHistoricalProcessExitReasons(ctx.packageName, 0, 8)
            else emptyList()
            Log.i("WireDashAutoProbe", JSONObject().put("exits", JSONArray(exits.map {
                JSONObject().put("process", it.processName).put("reason", it.reason)
                    .put("status", it.status).put("importance", it.importance).put("timestamp", it.timestamp)
            })).toString())
            pending.finish()
            return
        }
        if (cmd == "removePhoneTask") {
            // Same OS task-removal operation as swiping Recents, debug only.
            val tasks = ctx.getSystemService(ActivityManager::class.java).appTasks
                .filter { it.taskInfo.baseActivity?.className == MainActivity::class.java.name }
            tasks.forEach { it.finishAndRemoveTask() }
            Log.i("WireDashAutoProbe", JSONObject().put("probe", intent.getStringExtra("probe"))
                .put("removedTasks", tasks.size).toString())
            pending.finish()
            return
        }
        if (cmd in setOf("carCatalog", "carOpen", "carCommand", "carClose")) {
            val args = buildMap<String, Any> {
                intent.getStringExtra("dashboardId")?.let { put("dashboardId", it) }
                intent.getStringExtra("controlId")?.let { put("controlId", it) }
                intent.getStringExtra("actionId")?.let { put("actionId", it) }
                if (cmd == "carCommand") put("expiresAt", System.currentTimeMillis() + 5_000)
            }
            ShortcutEngine.car(ctx, cmd!!, args) { raw ->
                val result = try { JSONObject(raw) } catch (_: Exception) { JSONObject().put("outcome", "error") }
                val controls = result.optJSONArray("controls")
                val control = (0 until (controls?.length() ?: 0)).map { controls!!.getJSONObject(it) }
                    .firstOrNull { it.optString("id") == intent.getStringExtra("controlId") }
                val state = control?.optString("state")?.takeIf { it in setOf("ON", "OFF", "OPEN", "CLOSE", "STOP") }
                // Counts and normalized state only; no saved names, topics or credentials.
                Log.i("WireDashAutoProbe", JSONObject().put("probe", intent.getStringExtra("probe"))
                    .put("method", cmd).put("ms", System.currentTimeMillis() - tap)
                    .put("outcome", result.optString("outcome", "ok"))
                    .put("dashboards", result.optJSONArray("dashboards")?.length() ?: 0)
                    .put("controls", controls?.length() ?: 0)
                    .put("connected", result.optBoolean("connected")).put("state", state).toString())
                pending.finish()
            }
            return
        }
        val home = intent.getStringExtra("home") ?: return pending.finish()
        val done = { json: String ->
            Log.i("ZigDashShortcuts", "{\"ms\":${System.currentTimeMillis() - tap},\"result\":$json}")
            pending.finish()
        }
        when (cmd) {
            "scene" -> ShortcutEngine.scene(ctx, home, intent.getStringExtra("scene") ?: "", done)
            else -> ShortcutEngine.toggle(ctx, home, intent.getStringExtra("ieee") ?: "", done)
        }
    }
}
