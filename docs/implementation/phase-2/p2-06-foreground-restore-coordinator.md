# P2-06 — Foreground workout restore coordinator

**Status:** Draft [PR #22](https://github.com/mishraaditya595/northstar-health/pull/22), not merged or deployed. P2-06 is not feature complete.

## Behavior

The existing `WorkoutUploadCoordinator` is now the single authenticated foreground worker for **upload then restore**. It mounts only inside `BoundAccountWorkoutApp` with a verified account-specific ObjectBox Store. First launch, return from background, restored/renewed cloud session, workout finish and the existing 45-second foreground retry timer all invoke the same single-flight `drain()` loop. No OS background or terminated-app work is claimed.

1. Perform the existing durable historical backfill and upload pass (max 25 operations, with unchanged idempotent ACK/CAS validation).
2. If any pending local outbox operation remains, **defer** restore without advancing a cursor or persisting a false remote conflict. The importer's independent per-workout guard protects blocked/conflicted local operations.
3. Read the last durable owner-bound `cursorEpoch`, `nextCursor` and `blockedCode`. If blocked, make no RPC: only a separately reviewed/user-approved explicit `clearBlocked` can recover it.
4. Request `get_workout_changes` through the merged authenticated `WorkoutRestoreTransport` (100 changes per page; 20-second timeout). Both transport and worker recheck live JWT/account identity after the network response. Re-check the outbox **again immediately before the synchronous ObjectBox import**, so a newly saved local operation during the RPC defers the page safely.
5. Call the merged `ObjectBoxWorkoutRestoreImporter.applyPage`. Workout/exercise/set/remote revision/tombstones and cursor commit in one write transaction, with no outbox re-enqueue. Imported history invalidates the `completedWorkoutHistoryProvider` so an already-open Progress tab does not remain stale.
6. Loop while `hasMore` is true, up to four pages per pass. A cursor-reset response atomically changes the epoch and cursor to zero; then fetch from zero under the new epoch. More pages schedule a rerun through the existing serialized worker. Invalid no-progress and repeated-reset conditions halt the pass.
7. Decoder `RestoreContractException.code` becomes a durable, static, non-PII blocked reason if the request still owns the cursor; importer conflicts already persist their own reason. Auth/timeout/RPC/unexpected transport errors are retryable foreground failures and **never advance or unblock the cursor**.

### Serialization & limitations

Upload RPC/ACK and restore RPC/import run sequentially in one foreground worker. No second restore timer or parallel pull is mounted. Local workout editing remains offline-first, and the importer protects dirty edits. This design prioritizes local uploads and may delay restore indefinitely if an upload cannot be acknowledged; starvation and explicit conflict/dependency recovery are a later P2-06 task. A terminal blocked upload for a distinct workout can also block a matching remote change, with explicit recovery deferred to P2-07.

`lastRestoreFailureKind` is a volatile diagnostic code only; durable restore blockers stay in ObjectBox. There is deliberately **no automatic unblock, last-write-wins, deletion command, skip, raw payload logging, or unauthenticated read**.

### Verification

Host Flutter tests use a real file-backed ObjectBox Store and fake authenticated transport; cover first import and reopening, 100-row pagination, epoch reset, upload-first ordering, failed-upload defer, new upload during fetch, signout/account switch while waiting, offline retry with same cursor, permanent malformed-feed blockers and preservation of an existing unfinished workout. Existing importer and uploader tests remain required.

**Not run / release gates:** signed-in multi-device Supabase network E2E, actual Android/iOS app resume/force-stop persistence, server hosting migration drift reconciliation, lower-memory device profiling and load. The repository's AGENTS.md requires actual device tests before release; Linux host tests are not substitutes.

### Rollback

Unmount the restore transport/importer from the account-bound coordinator while leaving the P2-04 uploader unchanged. Keep all local state, pending operations and remote tombstones; do not delete user workout data or rewrite applied SQL migrations.

### Deferred

Queue fairness beyond first 500 rows, resumable conflict resolution and deletion commands, P2-07 account/export/deletion/status UX and P2-08 device, auth/RLS and release verification remain open.
