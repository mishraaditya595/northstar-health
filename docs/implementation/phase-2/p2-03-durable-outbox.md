# P2-03 · Durable completed-workout outbox and auth pausing

**Status:** PR #15 — **merged**. Native/device release QA remains outstanding; network uploading is in P2-04 (draft PR #16).  
**Policy:** [ADR-0005](../../adr/0005-mandatory-auth-and-workout-sync.md) governs scope. Only NorthStar-authored **completed** phone workouts may enter cloud-bound operations. In-progress, paused, discarded, watch-imported and platform health data remain local.

## Delivered

- New ObjectBox entity `WorkoutSyncOutboxEntity` is an **additive schema change**; the numeric IDs / UIDs of all existing entities and properties must remain unchanged. The generated `objectbox.g.dart` and `objectbox-model.json` must be reviewed together. The frozen pre-index fixture is not regenerated.
- `ObjectBoxWorkoutOutbox.enqueueCompletedInTransaction` requires an already-completed, nondeleted NorthStar phone workout, hydrates exercise / set snapshots from the same Store, constructs the strict P2-01 version-1 JSON payload (no plans, rest timers, auth tokens or health samples), then writes an immutable operation in the **same ObjectBox write transaction**. If its DTO is incompatible (invalid UUID, excessive counts/size, Unicode name limit, timestamp before workout start, etc.), **local completion still commits** alongside a durable `blocked` receipt with no uploadable payload. Pending uploads exclude blocked receipts; the completed workout is never discarded. Actual ObjectBox transaction failures still abort the whole finish.
- All production finish entrypoints (the live engine and the deprecated session repository primitive) use the `workoutOutboxProvider`. Duplicate identical finish retries do not enqueue again. Starting, pausing, resuming, modifying a set **before finish**, and discarding do not enqueue.
- Rows have indexed `state` (`pending`, `blocked`, `acknowledged`); pending queries use an indexed, bounded batch (max 500, default 100), not a full database scan. The ObjectBox query orders by `createdAtMs`, then `localRevision`, `sessionUuid` and `operationUuid` **before** applying the limit, making same-timestamp boundaries deterministic. Rows include stable operation UUID, session UUID, local revision, immutable JSON snapshot, event timestamps, state and eventual server receipt metadata; pending reads survive app restart. `acknowledge` matches operation UUID + client revision and a nonzero server response before changing a row from pending to acknowledged. Network sending and queue compaction are **not** implemented; acknowledgment is API scaffolding only and must not be called until P2-04 validates an actual server reply.
- ObjectBox stores are physically partitioned by Supabase host and account UUID (P2-02), so operations and local training data never appear in another account's store. SDK sign-out leaves pending operations in the original partition.
- `AccountAuthController` listens to Supabase session changes, exposes `cloudBackupReady` and `backupPaused`, and immediately locks the local workout UI if a different logged-in account appears. An absent/expired JWT never allows cloud transfer, but a previously verified local user can continue training offline. Supabase stream errors trigger an immediate pause and notification; even a different account with an expired JWT locks the prior store. Today uses the design kit's `InsightCard` and `ListenableBuilder` to show *Session expired — backup paused*, plus a local-only warning for non-uploadable finished sessions. The workout finish action invalidates `blockedWorkoutCountProvider` immediately after a successful local commit, so Today displays newly blocked workouts without an app restart; a route-based widget regression test confirms this. The pending queue is not transmitted by this milestone.

## Storage and retry semantics

```text
finish completed phone workout
  └─ one ObjectBox write transaction
       ├─ set completed state/revision and remove local recovery checkpoint
       ├─ serialize validated exercise/set snapshots
       └─ append pending immutable operation (valid DTO) OR blocked local receipt (invalid DTO)
  └─ commit only if all parts succeed

app restart / sign out / offline
  └─ original owner's queue stays durable and untouched

future P2-04 worker
  └─ authenticated same owner, valid token only
  └─ send in per-workout local revision order; resolve P2-01 expected server revision
  └─ persist exact server acknowledgement / conflict in one local transaction
```

**Cloud retention:** Only completed workouts qualify. The queue metadata and payload are user-authored workout information and must never be logged. A worker must not clear a pending row upon HTTP 200 alone; it requires an actual applied ACK with matching operation identity and server revision. A stale replay must never acknowledge a newer local operation. On server conflict, retain both local and remote versions for explicit reconciliation — no silent last-write-wins.

## Verification checklist

- Full native ObjectBox tests: completed snapshot + pending operation committed together; failed cloud compatibility commits **completed + blocked** (local-first). Database write failures still roll back.
- Start, pause and discard generate no work; duplicate finish retries generate no duplicate.
- Pending operation and UUID persist over restart; invalid ACK does not dequeue; valid ACK is idempotent.
- Tests exercise populated account A/B stores across reopen, plus a frozen exact main/PR #14 base-model schema fixture upgraded to the new model.
- Server-compatible validation (UTF-8 + jsonb whitespace headroom, Unicode code points, start-before-set chronology, 120 exercises/300 sets, 64 KiB) and InsightCard widget tests added.
- Local fixture compatibility tests and `lib/objectbox-model.json` UID diff reviewed (existing UIDs must be preserved).
- `flutter analyze`, `dart format`, `flutter test`, Android APK and Wear OS CI pass. iOS build/device and sign-in/out must be checked before release.

## Remaining for P2-04 and beyond

No Supabase RPC is called; no backup uploads occur yet. The sync worker must **never** transmit `blocked` receipts and must implement user-visible recovery actions for them. It must define strict per-account retry ordering and last server revision, online session revalidation, exponential backoff, conflict and deletion handling, user-facing queue status and integration tests. Future edits to already-completed sessions must enqueue a **new immutable operation** in their own local transaction. Until such an edit/delete command is implemented, the source has no post-completion mutation path and no deletion tombstone queue path. Backfill for completed sessions predating P2-03 requires an explicit one-time audited migration strategy, not silent bulk uploads from arbitrary local root databases.

**Security:** No service role, API secret, access token or database password belongs in Git or a Flutter build. Only the publishable URL/key from P2-02 is permitted. Revoke/expired sessions pause upload; remote RLS is authoritative.

## Rollback

Do not reset or delete local ObjectBox data, overwrite or reset UIDs, or silently detach pending operations. If required, disable the future upload worker and ship a tested forward migration. Before declaring this milestone complete, native old-model upgrades must demonstrate retained workout history.
