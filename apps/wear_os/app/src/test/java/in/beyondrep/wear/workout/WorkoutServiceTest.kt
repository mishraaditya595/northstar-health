package `in`.beyondrep.wear.workout

import android.Manifest
import android.app.Application
import androidx.test.core.app.ApplicationProvider
import `in`.beyondrep.wear.exercise.WorkoutService
import `in`.beyondrep.wear.exercise.WorkoutServiceControl
import `in`.beyondrep.wear.exercise.WorkoutServiceState
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * On Android 14 a `health` foreground service throws SecurityException without a sensor
 * permission: the workout must record without the service instead of crashing.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WorkoutServiceTest {
    private val app: Application = ApplicationProvider.getApplicationContext()

    @Before
    fun reset() = WorkoutServiceState.ended()

    @After
    fun clean() = WorkoutServiceState.ended()

    private fun denySensors() =
        shadowOf(app).denyPermissions(Manifest.permission.BODY_SENSORS, Manifest.permission.ACTIVITY_RECOGNITION)

    @Test
    fun withoutSensorPermissionsTheServiceIsNotStarted() {
        denySensors()
        assertFalse(WorkoutServiceControl.mayRunHealthService(app))
        WorkoutServiceControl(app).startForeground()
        assertNull(shadowOf(app).nextStartedService)
    }

    @Test
    fun oneSensorPermissionIsEnoughToStartTheService() {
        denySensors()
        shadowOf(app).grantPermissions(Manifest.permission.ACTIVITY_RECOGNITION)
        assertTrue(WorkoutServiceControl.mayRunHealthService(app))
        WorkoutServiceControl(app).startForeground()
        assertNotNull(shadowOf(app).nextStartedService)
    }

    @Test
    fun aServiceStartedWithoutPermissionStopsItselfInsteadOfCrashing() {
        denySensors()
        val controller = Robolectric.buildService(WorkoutService::class.java).create()
        controller.startCommand(0, 1)
        assertTrue(shadowOf(controller.get()).isStoppedBySelf)
    }

    @Test
    fun aStopBeforeTheServiceIsInTheForegroundIsRememberedNotSent() {
        shadowOf(app).grantPermissions(Manifest.permission.BODY_SENSORS)
        val control = WorkoutServiceControl(app)
        control.startForeground()
        control.stop()
        assertNull(shadowOf(app).nextStoppedService, "stopService before startForeground would crash the app")
        // The service reports it is in the foreground: it learns of the stop and ends itself.
        assertTrue(WorkoutServiceState.enteredForeground())
    }

    @Test
    fun aStopAfterTheServiceIsInTheForegroundStopsIt() {
        shadowOf(app).grantPermissions(Manifest.permission.BODY_SENSORS)
        WorkoutServiceState.starting()
        assertFalse(WorkoutServiceState.enteredForeground())
        WorkoutServiceControl(app).stop()
        assertNotNull(shadowOf(app).nextStoppedService)
    }
}
