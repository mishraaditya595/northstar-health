# P2-06 — Fair upload-queue scanning and revision dependencies

**Status:** Implementation in the draft PR opened for this slice, not merged or deployed. PR #22 is merged into main; this is the next independent P2-06 workstream.

## Problem

The P2-04 `ObjectBoxWorkoutOutbox.reserveNext()` reads only the oldest 500 `pending` rows. If every row in that window is within its retry cooldown, or a later local revision is blocked by an earlier workout revision, an eligible upload at row 501+ is never considered. This is local starvation and can delay the account's restore because the foreground sync coordinator prioritizes pending uploads.

## Implementation scope

- Use ObjectBox `Query.offset` and `Query.limit` to scan the entire eligible queue through **fixed windows of 500**, within the current owner-bound write transaction. Query order remains creation time, local revision, workout UUID and operation UUID. Only one page is retained in Dart memory at a time. A single `reserveNext` may inspect multiple windows; it does not impose an artificial first-500 ceiling.
- The scan includes `pending` and durable `dependency_paused` rows. If a workout's lower revision remains unacknowledged (including a conflict, a blocked operation or a retrying upload), mark the successor `dependency_paused` with the static `predecessor_unresolved` code and **preserve its operation UUID, payload, attempts and last-attempt time**.
- When the earlier revision is acknowledged, the next reservation moves the dependent row back to `pending`, clears that diagnostic and sends it using the latest acknowledged server revision (or the imported remote CAS baseline). A previously conflicting predecessor is **never** auto-ACKed or automatically resolved: a separately reviewed recovery workflow must do that.
- If a lower pending revision has already been overtaken by a **higher acknowledged** revision, terminally block the lower operation with `later_revision_acknowledged`. Never send old content past a newer durable ACK.
- Query pagination adjusts its offset for rows that become terminally blocked during the scan, avoiding off-by-one skips. No consumer-level queue deletion, cross-workout reordering constraint, or silent data loss.
- Include `dependency_paused` in existing `syncFlags()` as unsynced; any same-workout predecessor `conflict` or `blocked` still wins the existing **Needs review** / **Local only** label.
- No additional ObjectBox entity or generated model UID change, no server SQL change, no new library.

## Safety and tradeoffs

A long backlog may require multiple 500-record ObjectBox queries in **one synchronous transaction** until the first eligible operation is found; memory is bounded per query page, but total scan time is proportional to the number of queued candidates. Do not claim this guarantees fixed-duration scans under arbitrarily large backlogs. No network call is performed inside the reservation transaction, and the upload coordinator remains single-flight with restore.

A dependency-paused item remains unacknowledged and is never mistaken for a cloud ACK. A conflicting or blocked predecessor continues to require user-reviewed resolution; it is not implicitly retried. This PR makes **fairness and dependencies** reliable, not automatic conflict resolution or deletion.

## Test plan and evidence

File-backed ObjectBox host tests using synthetic UUIDs, payloads and explicit clocks:

1. 500 earliest rows in backoff cannot starve the next eligible workout.
2. 500 dependency-paused later revisions cannot starve another workout.
3. Paused dependency survives Store restart and sends with the correct server CAS expectation after reviewed predecessor ACK.
4. Blocking a full invalid window does not skip the next row shifted into the scanned offset.
5. Lower local revision cannot send when a later revision has already been ACKed.
6. Repeated paused scans leave operation UUID/payload, attempts and timestamps unchanged, and UI flags remain appropriate.
7. Account-separated physical Stores do not share ordering or state.

Also run all existing uploader, importer, Flutter widget and native ObjectBox tests. **Physical iOS/Android testing, real signed-JWT Supabase recovery, hosted migration deployment and performance profiling remain unrun release gates.**

## Next reviewable slices

1. **Remote deletion and tombstones**: explicit completed-workout deletion command, atomic local tombstone/outbox, server CAS and authenticated two-device deletion tests.
2. **Conflict / skipped restore recovery**: user-reviewable local/remote versions, safe explicit resolution with `WorkoutRestoreSkipEntity`, re-fetch of server state and dependent queue release; never clear a conflict by simply deleting the receipt.
3. P2-07 account/sync recovery status, export/account deletion; P2-08 hosted rollout, privacy/security and physical-device QA.

No force-push, deployment, automatic merge or production database changes from this implementation slice.
