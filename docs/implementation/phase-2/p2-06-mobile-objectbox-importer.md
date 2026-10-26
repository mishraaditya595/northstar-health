# P2-06 — Owner-scoped transactional ObjectBox restore importer

**Status:** Implementation under review in [PR #20](https://github.com/mishraaditya595/northstar-health/pull/20). This slice is **NOT** a running automatic restore feature and is **NOT** deployed.

## What this slice adds

- `WorkoutRestoreCursorEntity`: durable, account-specific `cursorEpoch`, `nextCursor`, `blockedCode` and `blockedAtMs`. The ObjectBox Store is already physically separated by authenticated account; the importer additionally checks the active account and refuses cross-owner cursor reuse.
- `WorkoutRemoteStateEntity`: per-workout server CAS revision, change sequence, epoch, imported **local** revision and deletion/tombstone state. This includes unknown tombstones (without creating phantom history). Never assign remote server revision to local `WorkoutSessionEntity.revision`.
- `ObjectBoxWorkoutRestoreImporter.applyPage`: consumes the already-validated `WorkoutRestorePage` from merged PR #19. All session/exercise/set changes, the remote metadata and the page's epoch+cursor are written in **one ObjectBox transaction**. Failure at any point rolls everything back. There is no network operation, timer, app listener, background task or upload enqueue.
- `ObjectBoxWorkoutOutbox.backfillCompleted()` excludes workouts already tracked in imported remote metadata. This guard is durable across restart; restored records cannot be re-enqueued as newly finished phone workouts.
- Tombstones soft-delete eligible local sessions and persist the server's revision and sequence; unseen tombstones create only metadata. An upsert following a known tombstone is **not** automatically resurrected.
- Stale page replay cannot rewind the committed cursor. Page application checks the request cursor and epoch against the account's durable state, including reset controls.
- Local workouts with pending, blocked or conflicting operations, unknown baseline, changed local optimistic revision, missing tracked records, cross-workout exercise/set UUID collision, or newer local acknowledged revision after server rollback are **blocked**, not overwritten.

## Failure and recovery contract

- Decode malformed data *before* invoking the importer. On decoder failure, a future foreground pull coordinator invokes `recordBlocked(afterSeq, requestedEpoch, code)`, which saves **only a stable non-PII reason code** against the still-matching persisted cursor. The code is not a permission to skip a page.
- If the importer itself detects a deterministic conflict, its write transaction rolls back. An independent owner-scoped transaction stores the bounded error code, keeping the old epoch/cursor and all local data intact. The caller must **stop automatic retries** and show recovery later in P2-07.
- On authentication switch or a stale concurrent cursor, no blocker is recorded for the new account. The network transport still independently performs its pre/post-RPC authorization checks.
- **Epoch reset** commits the new epoch and zero cursor without deleting any local or remote metadata. Replaying remote rows checks the stored epoch and revisions; a rollback to older server revisions blocks rather than destroys a newer local snapshot. The privileged rotation runbook remains mandatory after PITR.
- Manual operator correction/review is required for persistent corruption, canonical UUID collisions, newer-local-versus-older-server histories and unresolved dirty local edits. There is no automatic destructive row skip or conflict merge.

## Native regression coverage

- Atomic import and cursor persistence; restart; replay idempotency; stable remote/local revision separation.
- Fault injection immediately before commit to demonstrate rollback of *all* changes.
- Unknown/new-device and known workout tombstones, no resurrection or phantom history.
- Dirty outbox, untracked local and manually changed local optimistic revision failures, plus acknowledged-server correction.
- Owner switching/cross-owner Store reuse, reset/PITR rollback protection, persistent blocked reason codes and retry.
- UUID collision rollback, prevention of historical upload backfill.
- Actual ObjectBox on-disk schema upgrade from the committed frozen **pre-outbox** generated model, not only a clean database test. Original entity, property and index UIDs remain frozen. Commit the new model JSON and generated bindings together.

## Explicit non-goals and release blockers

This PR **does not activate** the restore transport, register an app lifecycle pull coordinator, provide automatic pagination/network retry, or resolve conflict UI. It intentionally does not implement the upload-worker serialization, outbox first-500 fairness, deletion-command UX, account data export/deletion, or real multi-device tests. All remain open in P2-06/P2-07/P2-08.

**Before deployment:** check current hosted Supabase migrations and apply approved seventh, eighth, ninth migrations in order to a controlled environment; run live signed-JWT owner-isolation tests, concurrent updates, account switching and Android/iOS physical-device process-death QA. Do not merge, deploy or change production data automatically from this PR.
