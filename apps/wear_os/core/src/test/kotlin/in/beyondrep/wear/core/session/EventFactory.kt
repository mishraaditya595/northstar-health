package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.contracts.EventHeader
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WorkoutEventV2
import `in`.beyondrep.wear.core.contracts.WorkoutStartedPayload
import java.time.Instant

/**
 * Builds synthetic workout events by hand, with the sequence and timestamps a SessionMachine would
 * write, for tests that run before (or independent of) the machine.
 */
class EventFactory(
    private val workoutId: String = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    private val sessionId: String = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    private val timeZone: String = "Asia/Kolkata",
    var now: Instant = Instant.ofEpochSecond(1_792_000_000),
) {
    private var sequence = 0
    val events = mutableListOf<WorkoutEventV2>()

    private fun header(): EventHeader {
        val n = sequence++
        val stamp = now.toString()
        return EventHeader(
            eventId = "99999999-2222-4222-8222-%012d".format(n + 1), workoutId = workoutId, sessionId = sessionId,
            originDeviceId = "watch-installation-a", sequence = n, occurredAtUtc = stamp, recordedAtUtc = stamp,
            timeZone = timeZone)
    }

    private fun <T : WorkoutEventV2> add(event: T): T = event.also { events.add(it) }

    fun start(template: WorkoutTemplate, owner: String = "watch", accountKey: String = "0123456789abcdef".repeat(4)) {
        add(
            WorkoutEventV2.WorkoutStarted(
                header(), WorkoutStartedPayload(name = template.name, owner = owner, accountKey = accountKey)))
        for (payload in template.exerciseAddedPayloads) add(WorkoutEventV2.ExerciseAdded(header(), payload))
    }

    fun log(values: SetValues) = add(WorkoutEventV2.SetLogged(header(), values))
    fun skip(setId: String) = add(WorkoutEventV2.SetSkipped(header(), setId))
    fun complete() = add(WorkoutEventV2.WorkoutCompleted(header()))
}
