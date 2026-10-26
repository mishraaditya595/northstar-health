# P2-06 — Foreground workout restore coordinator

**Status:** Draft [PR #22](https://github.com/mishraaditya595/northstar-health/pull/22), not merged or deployed. P2-06 is not feature complete.

## Behavior

The existing `WorkoutUploadCoordinator` is now the single authenticated foreground worker for **upload then restore**. It mounts only inside `BoundAccountWorkoutApp` with a verified account-specific ObjectBox Store. First launch, return from background, restored/renewed cloud session, workout finish and the existing 45-second foreground retry timer all invoke the same single-flight `drain()` loop. No OS background or terminated-app work is claimed.

1. Perform the existing durable historical backfill and upload pass (max 25 operations, with unchanged idempotent ACK/CAS validation).
2. If any local outbox operation is **`pending`**, defer restore without fetching or advancing the cursor; pending uploads clear on their own (or after backoff). `blocked` and `conflict` operations do **not** defer the feed (see ADR-0006): the importer skips only that workout's remote change, keeps the local copy and records a durable `WorkoutRestoreSkipEntity`, then imports the rest of the page.
3. Read the last durable owner-bound `cursorEpoch`, `nextCursor` and `blockedCode`. If blocked, make no RPC: only a separately reviewed/user-approved explicit `clearBlocked` can recover it.
4. Request `get_workout_changes` through the merged authenticated `WorkoutRestoreTransport` (100 changes per page; 20-second timeout). Both transport and worker recheck live JWT/account identity after the network response. Re-check for **pending** outbox operations immediately before the synchronous ObjectBox import (with no `await` in between), so a workout saved during the RPC defers the page; a workout that became conflicted or blocked during the RPC is skipped and recorded by the importer.
5. Call the merged `ObjectBoxWorkoutRestoreImporter.applyPage`. Workout/exercise/set/remote revision/tombstones and cursor commit in one write transaction, with no outbox re-enqueue. Imported history invalidates the `completedWorkoutHistoryProvider` so an already-open Progress tab does not remain stale.
6. Loop while `hasMore` is true, up to four pages per pass. A cursor-reset response atomically changes the epoch and cursor to zero; then fetch from zero under the new epoch. More pages schedule a rerun through the existing serialized worker. Invalid no-progress and repeated-reset conditions halt the pass.
7. Decoder `RestoreContractException.code` becomes a durable, static, non-PII blocked reason if the request still owns the cursor; importer conflicts already persist their own reason. Auth/timeout/RPC/unexpected transport errors are retryable foreground failures and **never advance or unblock the cursor**.

### Serialization & limitations

Upload RPC/ACK and restore RPC/import run sequentially in one foreground worker. No second restore timer or parallel pull is mounted. Local workout editing remains offline-first, and the importer protects dirty edits. A pending operation in exponential backoff can defer restore for roughly 21 minutes or until its next eligible retry. A terminal `blocked`/`conflict` operation never pauses the account: its workout's remote change is skipped and recorded (server change sequence, epoch, tombstone flag) so a later reviewed resolution can re-fetch the server version; a later successfully applied change for that workout removes the record. The skip is never silent: the workout is tagged **Not synced** in Progress and counted on Today with a **Sync now** action. No conflict resolution UI exists in PR #22.

`lastRestoreFailureKind` (including `upload_unresolved`, now meaning a pending upload) is a volatile diagnostic code only; durable restore blockers and skip records stay in ObjectBox. There is deliberately **no automatic unblock, last-write-wins, deletion command, raw payload logging, or unauthenticated read**.

### Verification

Host Flutter tests use a real file-backed ObjectBox Store and fake authenticated transport; cover first import, restart after an interrupted second page, 100-row pagination, four-page budget continuation, repeated epoch-reset guard, simulated concurrent cursor advancement / `restore_no_progress`, same-device uploaded ACK replay without local revision inflation, and real Riverpod completed-history provider invalidation. They also cover upload-before-restore, pending uploads before and *during* a pull, a blocked upload for an unrelated workout not stopping restore, conflicted/blocked workouts in the feed being skipped and recorded while others import, a conflict created during a pull, a later applied change clearing its skip record, per-drain sync-tag refresh, offline retry, mid-flight account switch **and token expiry**, permanent malformed-feed blockers, preservation of an in-progress local workout, and paired-dependency assertion. Widget tests cover the Progress/detail **Not synced**/**Local only** tags and the Today **Sync now** notice (hidden while backup is paused). Existing importer and uploader tests remain required.

**Not run / release gates:** signed-in multi-device Supabase network E2E, actual Android/iOS app resume/force-stop persistence, server hosting migration drift reconciliation, lower-memory device profiling and load. The repository's AGENTS.md requires actual device tests before release; macOS/Linux host tests are not substitutes.

### Rollback

Unmount the restore transport/importer from the account-bound coordinator while leaving the P2-04 uploader unchanged. Keep all local state, pending operations and remote tombstones; do not delete user workout data or rewrite applied SQL migrations.

### Deferred

Queue fairness beyond first 500 rows, resumable conflict resolution and deletion commands, P2-07 account/export/deletion/status UX and P2-08 device, auth/RLS and release verification remain open.
