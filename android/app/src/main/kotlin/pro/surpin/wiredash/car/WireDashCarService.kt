package pro.surpin.wiredash.car

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import pro.surpin.wiredash.MainActivity
import pro.surpin.wiredash.R

/** Projected Android Auto IoT app. The phone app remains the setup/editor UI. */
class WireDashCarService : CarAppService() {
    private val connections = mutableSetOf<Any>()
    private var foreground = false

    // Do not initialize Flutter in Service.onCreate(): the host's bind and
    // handshake must finish before cold VM/plugin work is queued. The first
    // visible screen requests the engine asynchronously itself.
    override fun onCreate() {
        super.onCreate()
        Log.i("WireDashAuto", "car service created; Flutter initialization deferred")
    }

    override fun createHostValidator(): HostValidator =
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(this)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(): Session = newSession(::EngineCarBridge)

    internal fun newSession(bridgeFactory: (CarContext) -> CarBridge): Session = object : Session() {
        override fun onCreateScreen(intent: Intent): Screen {
            val bridge = bridgeFactory(carContext)
            val connection = Any()
            lifecycle.addObserver(object : DefaultLifecycleObserver {
                override fun onStart(owner: LifecycleOwner) {
                    connectionStarted(connection)
                }
                override fun onStop(owner: LifecycleOwner) {
                    // Release car subscriptions. The cached engine may still
                    // serve phone widgets; it is not destroyed here.
                    connectionStopped(connection)
                    if (connections.isEmpty()) bridge.call("carClose") {}
                }
                override fun onDestroy(owner: LifecycleOwner) {
                    connectionStopped(connection)
                }
            })
            return DashboardCarScreen(carContext, bridge)
        }
    }

    internal fun connectionStarted(connection: Any) {
        connections.add(connection)
        if (foreground) return
        try {
            val notifications = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) notifications.createNotificationChannel(
                NotificationChannel(CHANNEL, getString(R.string.car_connection_channel), NotificationManager.IMPORTANCE_LOW))
            val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
                else @Suppress("DEPRECATION") Notification.Builder(this))
                .setSmallIcon(R.drawable.ic_shortcut_tile).setContentTitle("WireDash")
                .setContentText(getString(R.string.car_connection_active)).setContentIntent(open)
                .setCategory(Notification.CATEGORY_SERVICE).setOngoing(true).setOnlyAlertOnce(true).build()
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else startForeground(NOTIFICATION, notification)
            foreground = true
            Log.i("WireDashAuto", "car connection foreground=true sessions=${connections.size}")
        } catch (error: RuntimeException) {
            // Some hosts/OEMs can reject foreground promotion. Keep the native
            // loading/reconnect UI alive instead of crashing the car service.
            Log.w("WireDashAuto", "Car foreground promotion rejected: ${error.javaClass.simpleName}")
        }
    }

    internal fun connectionStopped(connection: Any) {
        connections.remove(connection)
        if (connections.isNotEmpty() || !foreground) return
        stopForeground(STOP_FOREGROUND_REMOVE)
        foreground = false
        Log.i("WireDashAuto", "car connection foreground=false")
    }

    override fun onDestroy() {
        try { super.onDestroy() } finally {
            connections.clear()
            if (foreground) stopForeground(STOP_FOREGROUND_REMOVE)
            foreground = false
        }
    }

    companion object {
        private const val CHANNEL = "android-auto-connection"
        internal const val NOTIFICATION = 41
    }
}
