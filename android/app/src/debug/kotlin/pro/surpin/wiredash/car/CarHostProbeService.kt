package pro.surpin.wiredash.car

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.HandshakeInfo
import androidx.car.app.IAppHost
import androidx.car.app.IAppManager
import androidx.car.app.ICarApp
import androidx.car.app.ICarHost
import androidx.car.app.IOnDoneCallback
import androidx.car.app.ISurfaceCallback
import androidx.car.app.OnDoneCallback
import androidx.car.app.constraints.IConstraintHost
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.SectionedItemTemplate
import androidx.car.app.model.TemplateWrapper
import androidx.car.app.serialization.Bundleable
import org.json.JSONObject
import pro.surpin.wiredash.R

/** Debug-only protocol host, in a separate process; no renderer or phone Activity. */
class CarHostProbeService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private var car: ICarApp? = null
    private var manager: IAppManager? = null
    private var bound = false
    private var closed = false
    private var reading = false
    private var rows = emptyList<Row>()
    private var worstMs = 0L
    private val poll = object : Runnable {
        override fun run() {
            requestTemplate()
            if (!closed) main.postDelayed(this, 250)
        }
    }
    private val done = object : OnDoneCallback {}
    private val appHost = object : IAppHost.Stub() {
        override fun invalidate() { main.post { requestTemplate() } }
        override fun showToast(text: CharSequence, duration: Int) {
            main.post { emit(JSONObject().put("phase", "toast")
                .put("working", text.toString().endsWith(getString(R.string.car_working)))) }
        }
        override fun setSurfaceCallback(callback: ISurfaceCallback?) {}
        override fun sendLocation(location: Location) {}
        override fun showAlert(alert: Bundleable) {}
        override fun dismissAlert(alertId: Int) {}
        override fun openMicrophone(request: Bundleable): Bundleable = throw UnsupportedOperationException("IoT probe")
        override fun getInterfaceVersion() = IAppHost.VERSION
    }
    private val constraints = object : IConstraintHost.Stub() {
        override fun getContentLimit(type: Int) = 100
        override fun isAppDrivenRefreshEnabled() = true
        override fun getInterfaceVersion() = IConstraintHost.VERSION
    }
    private val host = object : ICarHost.Stub() {
        override fun getHost(type: String): IBinder = when (type) {
            CarContext.APP_SERVICE -> appHost.asBinder()
            CarContext.CONSTRAINT_SERVICE -> constraints.asBinder()
            else -> throw IllegalArgumentException("Unsupported IoT probe host")
        }
        override fun startCarApp(intent: Intent) {}
        override fun finish() {}
        override fun getInterfaceVersion() = ICarHost.VERSION
    }
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            car = ICarApp.Stub.asInterface(binder)
            car!!.onHandshakeCompleted(Bundleable.create(HandshakeInfo(packageName, 8)), callback("handshake") {
                car!!.onAppCreate(host, Intent(), resources.configuration, callback("create") {
                    car!!.getManager(CarContext.APP_SERVICE, callback("manager") { response ->
                        manager = response as IAppManager
                        car!!.onAppStart(callback("start") {
                            car!!.onAppResume(callback("resume") {
                                main.removeCallbacks(poll)
                                main.post(poll)
                            })
                        })
                    })
                })
            })
        }
        override fun onServiceDisconnected(name: ComponentName) {
            manager = null
            car = null
            reading = false
            emit(JSONObject().put("phase", "disconnected"))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val notifications = getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(NotificationChannel("auto-probe", "Auto protocol test", NotificationManager.IMPORTANCE_LOW))
        val notification = Notification.Builder(this, "auto-probe").setSmallIcon(R.drawable.ic_shortcut_tile)
            .setContentTitle("WireDash Auto protocol test").setOngoing(true).build()
        startForeground(84, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.getStringExtra("cmd") ?: "start") {
            "start" -> if (!bound) {
                bound = bindService(Intent(CarAppService.SERVICE_INTERFACE).setComponent(
                    ComponentName(this, WireDashCarService::class.java)), connection, BIND_AUTO_CREATE or BIND_IMPORTANT)
                check(bound) { "Could not bind car service" }
            }
            "open" -> rows.firstOrNull { it.isBrowsable }?.onClickDelegate?.sendClick(done)
            "tap" -> rows.firstOrNull { it.toggle != null }?.toggle?.let {
                it.onCheckedChangeDelegate.sendCheckedChange(!it.isChecked, done)
            }
            "back" -> manager?.onBackPressed(callback("back"))
            "stop" -> {
                car?.onAppPause(callback("pause") {
                    car?.onAppStop(callback("stop") { stopSelf() })
                }) ?: stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun callback(phase: String, success: (Any?) -> Unit = {}): IOnDoneCallback {
        val started = SystemClock.uptimeMillis()
        return object : IOnDoneCallback.Stub() {
            override fun onSuccess(response: Bundleable?) {
                main.post {
                    if (closed) return@post
                    val ms = SystemClock.uptimeMillis() - started
                    worstMs = maxOf(worstMs, ms)
                    if (phase != "template") emit(JSONObject().put("phase", phase).put("ms", ms))
                    try { success(response?.get()) } catch (error: Exception) {
                        emit(JSONObject().put("phase", phase).put("failure", error.javaClass.simpleName))
                        Log.e("WireDashAutoProbe", "Protocol probe failed in $phase", error)
                    }
                }
            }
            override fun onFailure(response: Bundleable) {
                main.post {
                    reading = false
                    emit(JSONObject().put("phase", phase).put("failure", "host-call"))
                }
            }
            override fun getInterfaceVersion() = IOnDoneCallback.VERSION
        }
    }

    private fun requestTemplate() {
        val app = manager ?: return
        if (closed || reading) return
        reading = true
        app.getTemplate(callback("template") { response ->
            val wrapper = response as TemplateWrapper
            val template = wrapper.template
            val loading = when (template) {
                is SectionedItemTemplate -> template.isLoading
                is ListTemplate -> template.isLoading
                else -> false
            }
            fun complete(content: List<Row>) {
                rows = content
                reading = false
                emit(JSONObject().put("phase", "template").put("template", template.javaClass.simpleName)
                    .put("templateId", wrapper.id).put("loading", loading).put("rows", rows.size)
                    .put("toggles", rows.count { it.toggle != null })
                    .put("browsable", rows.count { it.isBrowsable })
                    .put("actions", rows.sumOf { it.actions.size }).put("worstMs", worstMs)
                    .put("iconFingerprint", rows.fold(1) { hash, row ->
                        row.actions.fold(31 * hash + (row.image?.hashCode() ?: 0)) { value, action ->
                            31 * value + (action.icon?.hashCode() ?: 0)
                        }
                    })
                    .put("known", rows.firstOrNull { it.toggle != null }?.texts?.none {
                        it.toString() == getString(R.string.car_unknown)
                    } ?: false)
                    .put("on", rows.firstOrNull { it.toggle != null }?.toggle?.isChecked))
            }
            if (template is SectionedItemTemplate) {
                val content = mutableListOf<Row>()
                fun read(index: Int) {
                    if (index == template.sections.size) { complete(content); return }
                    val delegate = template.sections[index].itemsDelegate
                    if (delegate.size == 0) { read(index + 1); return }
                    delegate.requestItemRange(0, delegate.size - 1, object : OnDoneCallback {
                        @Suppress("UNCHECKED_CAST")
                        override fun onSuccess(response: Bundleable?) {
                            main.post { content.addAll(response!!.get() as List<Row>); read(index + 1) }
                        }
                        override fun onFailure(response: Bundleable) {
                            reading = false
                            emit(JSONObject().put("phase", "items").put("failure", "range"))
                        }
                    })
                }
                read(0)
            } else if (template is ListTemplate) {
                complete((template.singleList?.items ?: template.sectionedLists.flatMap { it.itemList.items }).filterIsInstance<Row>())
            } else complete(emptyList())
        })
    }

    private fun emit(data: JSONObject) = Log.i("WireDashAutoHostProbe", data.put("at", System.currentTimeMillis()).toString())

    override fun onDestroy() {
        closed = true
        main.removeCallbacksAndMessages(null)
        if (bound) unbindService(connection)
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
