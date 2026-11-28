package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.FixtureLoader
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import kotlinx.serialization.json.JsonObject

/** Shared helpers for the template, cursor and controller tests (TemplateFixtures in WorkoutTemplateTests.swift). */
object TemplateFixtures {
    fun counterIds(from: Int = 1): () -> String {
        var n = from - 1
        return {
            n += 1
            "00000000-0000-4000-8000-%012d".format(n)
        }
    }

    fun planRaw(): JsonObject {
        val message = WatchMessage.decode(FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/plans_snapshot.json"))
        return (message.body as WatchMessageBody.PlansSnapshot).raw
    }

    fun template(): WorkoutTemplate =
        checkNotNull(WorkoutTemplate.fromPlan(planRaw(), "plan-synthetic-1", counterIds()))
}
