package pro.surpin.wiredash.car

import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Looper
import androidx.car.app.HandshakeInfo
import androidx.car.app.model.SectionedItemTemplate
import androidx.car.app.testing.SessionController
import androidx.car.app.testing.ScreenController
import androidx.car.app.testing.TestCarContext
import androidx.lifecycle.Lifecycle
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@LooperMode(LooperMode.Mode.PAUSED)
class WireDashCarServiceTest {
    @Test fun coldServiceBindsWithoutStartingFlutterAndVisibleSessionOwnsTheConnection() {
        val controller = Robolectric.buildService(WireDashCarService::class.java).create()
        val service = controller.get()
        val context = TestCarContext.createCarContext(RuntimeEnvironment.getApplication())
        context.updateHandshakeInfo(HandshakeInfo("com.google.android.projection.gearhead", 8))
        val methods = mutableListOf<String>()
        val bridge = object : CarBridge {
            override fun call(method: String, args: Map<String, Any>, done: (JSONObject) -> Unit) {
                methods.add(method)
                if (method == "carClose") done(JSONObject())
            }
        }
        val session = service.newSession { bridge }
        val lifecycle = SessionController(session, context, Intent()).moveToState(Lifecycle.State.RESUMED)
        val screen = context.getCarService(androidx.car.app.ScreenManager::class.java).top
        // SessionController controls the Session; its TestScreenManager does
        // not dispatch a screen's lifecycle like the production manager does.
        val screenLifecycle = ScreenController(screen).moveToState(Lifecycle.State.RESUMED)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue((screen.onGetTemplate() as SectionedItemTemplate).isLoading)
        assertEquals(listOf("carCatalog"), methods)
        assertNotNull(shadowOf(service).lastForegroundNotification)
        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE, service.foregroundServiceType)
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedActivity)
        screenLifecycle.moveToState(Lifecycle.State.CREATED)
        lifecycle.moveToState(Lifecycle.State.CREATED)
        assertTrue(shadowOf(service).isForegroundStopped)
        assertNull(shadowOf(service).lastForegroundNotification)
        assertEquals(listOf("carCatalog", "carClose"), methods)
        lifecycle.moveToState(Lifecycle.State.RESUMED)
        screenLifecycle.moveToState(Lifecycle.State.RESUMED)
        assertNotNull(shadowOf(service).lastForegroundNotification)
        screenLifecycle.moveToState(Lifecycle.State.DESTROYED)
        lifecycle.moveToState(Lifecycle.State.DESTROYED)
        controller.destroy()
    }

    @Test fun overlappingSessionsAndDuplicateStopsCannotReleaseAnotherConnection() {
        val controller = Robolectric.buildService(WireDashCarService::class.java).create()
        val service = controller.get()
        val first = Any()
        val second = Any()
        service.connectionStarted(first)
        service.connectionStarted(first)
        service.connectionStarted(second)
        service.connectionStopped(first)
        service.connectionStopped(first)
        assertNotNull(shadowOf(service).lastForegroundNotification)
        service.connectionStopped(second)
        assertTrue(shadowOf(service).isForegroundStopped)
        assertNull(shadowOf(service).lastForegroundNotification)
        controller.destroy()
    }

    @Test fun foregroundRejectionDoesNotCrashAndCanBeRetried() {
        val controller = Robolectric.buildService(WireDashCarService::class.java).create()
        val service = controller.get()
        shadowOf(service).setThrowInStartForeground(SecurityException("test rejection"))
        val connection = Any()
        service.connectionStarted(connection)
        assertNull(shadowOf(service).lastForegroundNotification)
        shadowOf(service).setThrowInStartForeground(null)
        service.connectionStarted(connection)
        assertNotNull(shadowOf(service).lastForegroundNotification)
        controller.destroy()
        assertNull(shadowOf(service).lastForegroundNotification)
    }
}
