# P2-06 — Completed workout deletion and cross-device tombstones

**Status:** Draft PR #24; NOT merged, deployed or device-verified. PR #23 (queue fairness) merged.

## User experience
A completed NorthStar phone workout has a **Delete workout** action on its details page. The shared `showNsConfirm` dialog explains that deleting immediately removes local history, queues a deletion for Supabase and other signed-in devices, can be delayed by paused backup / conflicts, and cannot be undone. Cancelling is a no-op. The details screen then invalidates the completed-history Riverpod provider, refreshes sync badges, kicks the existing authenticated foreground worker and navigates back when possible.

No action is exposed for health observations, imported third-party activity, unfinished sessions, plans or non-phone data.

## Atomic local data ownership
`ObjectBoxWorkoutOutbox.deleteCompletedWorkout(sessionUuid, expectedLocalRevision)` uses the account-bound ObjectBox Store and a **single write transaction** to:
- Require an existing, completed, non-deleted `northstar_phone` session and exact local optimistic revision.
- Preserve the session's minimal UUID, revision, origin, timestamps and soft-deleted flag for idempotency and the importer's anti-resurrection checks; redact name and plan identity.
- Purge locally stored workout exercise and set detail rows.
- Append exactly one durable `WorkoutSyncOutboxEntity` with `action='delete'`, `payloadJson='null'` and the next local revision. This immutable token decodes to an actual SQL/JSON null, as required by the existing server RPC. Never embed a deleted workout snapshot in the deletion request.
- An exception, including an invalid generated operation UUID, rolls back **all** local changes. Exact local retries return false without creating another command.

Pending previous upserts are **not silently deleted**, including an in-flight upload whose acknowledgement may have been lost. They must ACK first, after which the delete uploads with the correct server CAS revision. A conflicted/blocked predecessor pauses the delete until explicit resolution. Tombstone writes are sticky; a new upsert cannot resurrect the same UUID on the server.

**Acknowledged snapshot cleanup:** local deletion, late upload acknowledgement, and an imported remote tombstone all redact the JSON payload of **already acknowledged** upsert receipts in the same ObjectBox write transaction. Operation UUID, owner binding, action, local/server revision and change sequence remain for CAS. **Unacknowledged** payloads cannot be discarded automatically: a request may already have reached the server, and deleting its snapshot would make safe replay and remote deletion impossible. Consequently offline deletion is not immediate secure erasure of every queued copy; conflict review and complete account data-rights workflows remain P2-06/P2-07.

## Transport, restore and failure rules
No new SQL migration required. Existing P2-01 server `sync_workout` accepts `delete` only when `p_payload IS NULL`, checks owner JWT/RLS and expected server revision, records an idempotent receipt and produces a tombstone on success. The existing foreground worker now accepts the specific `delete`/`null` combination in addition to validated completed upsert DTOs. Uploads and restores remain single-flight and account-bound.

The importer already handles remote tombstones by soft-deleting eligible device records. For an **echo of a newly ACKed local deletion**, the latest matching ACK local revision takes priority over an older imported local revision so the tombstone cannot produce a false `local_revision_changed` blocker. Only a durable ACK for the exact incoming server revision qualifies; unacknowledged changes still fail closed.

**Important limitation:** a user can locally delete a workout while offline but the server may retain its existing copy until the queued operation succeeds. The UI must be truthful about this. A conflicting or blocked predecessor may hold the deletion indefinitely until reviewed conflict resolution (next P2-06 slice). Explicit account deletion/retention/export remain P2-07. Physical device tests and hosted Supabase two-account/delete race tests remain P2-08.

## Verification
- Real file-backed ObjectBox tests: local data redaction and children removal, durable null-payload delete enqueue, idempotency across store reopen, rollback before commit, stale revision / incomplete / non-phone rejection.
- Fake authenticated upload/restore tests: upsert then delete CAS ordering, local ACK replay with tombstone, imported remote CAS baseline, remote tombstone on second device.
- UI widget test: shared confirmation dialog cancel and confirmed delete, completed-history provider invalidation.
- CI must verify Dart format, Flutter analyze, all host ObjectBox/widget tests, Android debug build, repository contracts, Supabase SQL/RLS and watchOS proof.

**Unrun release gates:** real iOS/Android app lifecycle tests, physical owner-switch/process-death, real Supabase multidevice signed JWT, server migration drift reconciliation, low-end profiling and actual deletion latency while backup is offline/blocked.

## Deferred P2 remaining
1. P2-06 explicit conflict/restore-skip review and safe resolution (including pending deletion on a conflicted predecessor) and cross-device integration verification.
2. P2-07 account settings, understandable sync state/retry/recovery, authenticated workout JSON export, in-app account deletion and unsynced-data warnings.
3. P2-08 hosted rollout, schema/RLS/privacy/security checks, real iOS/Android devices, offline/restart/performance and production release signoff.
