package `in`.beyondrep.wear.core.session

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Port of OrphanSessionPolicyTests.swift. */
class OrphanSessionPolicyTest {
    @Test
    fun anOrphanWithNothingToRestoreOrFinishIsDiscarded() {
        assertTrue(OrphanSessionPolicy.shouldDiscard(restoredSession = false, unresolvedPendingFinish = false))
    }

    @Test
    fun aRestoredSessionOwnsTheExerciseSession() {
        assertFalse(OrphanSessionPolicy.shouldDiscard(restoredSession = true, unresolvedPendingFinish = false))
    }

    @Test
    fun anUnresolvedPendingFinishKeepsTheExerciseSession() {
        assertFalse(OrphanSessionPolicy.shouldDiscard(restoredSession = false, unresolvedPendingFinish = true))
    }
}
