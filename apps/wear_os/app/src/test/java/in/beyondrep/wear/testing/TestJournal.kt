package `in`.beyondrep.wear.testing

import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.session.TemplateExercise
import `in`.beyondrep.wear.core.session.TemplateSet
import `in`.beyondrep.wear.core.session.WorkoutTemplate
import `in`.beyondrep.wear.core.store.WatchJournal
import java.util.UUID

const val TEST_KEY = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const val OTHER_TEST_KEY = "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"

/** Binds the journal to a synthetic account, as the phone's `account_binding` would. */
fun WatchJournal.bindForTest(key: String = TEST_KEY, unit: String = "kg") {
    saveBinding(
        WatchMessage(UUID.randomUUID().toString(), "2026-10-23T01:00:00Z", key, WatchMessageBody.AccountBinding(unit)),
    )
}

/** One exercise with two working sets, fresh ids each call. */
fun syntheticTemplate(name: String = "Synthetic push"): WorkoutTemplate = WorkoutTemplate(
    name,
    exercises = listOf(
        TemplateExercise(
            "ex-1", "Bench press", "reps", null, 0,
            listOf(
                TemplateSet(UUID.randomUUID().toString(), 0, restSeconds = 60),
                TemplateSet(UUID.randomUUID().toString(), 1, restSeconds = 60),
            ),
        ),
    ),
)
