package `in`.beyondrep.wear.core.session

/**
 * Decides what a launch does with an exercise session (Health Services on Wear) that no journal
 * session explains: the app died between ending the journal session and ending the platform
 * session, for example a discard. Such a session stays alive and would keep running on the watch.
 */
object OrphanSessionPolicy {
    /**
     * True when the recovered platform session may be ended and discarded: no active or paused
     * session was restored for it, and no finished workout is still waiting to save from it (a
     * failed lookup or an unbound account leaves the question open, so nothing is thrown away).
     */
    fun shouldDiscard(restoredSession: Boolean, unresolvedPendingFinish: Boolean): Boolean =
        !restoredSession && !unresolvedPendingFinish
}
