# Supabase workout-only backup — implementation contract

**Status: adopted design; no backend tables, RPC, sign-in UI or sync code shipped in PR #2.** Implement only after ObjectBox workout repository, local outbox and account association are tested. See [ADR-0003](adr/0003-data-cloud-health.md).

## Scope and payload

**Allowed in Supabase:** completed NorthStar-created session metadata, exercise names/type snapshots, per-set reps/load/duration/RPE/RIR/rest and user notes needed to restore finished history, revisions and deletion tombstones. These records are **sensitive**. Explicit user authentication and transparent backup controls required.

**Forbidden in Supabase:** HealthKit/Health Connect heart-rate, sleep, HRV, steps, SpO₂, location trails, raw vitals, platform-imported workouts, chart caches, health permission/query tokens, in-progress checkpoints and local ObjectBox database files. Custom plans/exercise library remain local-only in MVP; include only snapshots *embedded in finished workouts*.

## Proposed logical tables (implementation must add reviewed migrations)

```text
workout_backups
  user_id UUID NOT NULL
  workout_id UUID NOT NULL
  revision BIGINT NOT NULL
  aggregate_version INT NOT NULL
  payload JSONB NOT NULL
  server_change_seq BIGINT NOT NULL
  updated_at TIMESTAMPTZ NOT NULL
  deleted_at TIMESTAMPTZ NULL
  PRIMARY KEY (user_id, workout_id)

workout_sync_operations
  user_id UUID NOT NULL
  operation_id UUID NOT NULL
  workout_id UUID NOT NULL
  assigned_revision BIGINT
  recorded_at TIMESTAMPTZ
  PRIMARY KEY (user_id, operation_id)
```

These are **conceptual**, not ready-to-deploy SQL. Enforce maximum payload size, required fields, numeric ranges, supported aggregate versions, ownership and authorized operations. Implement a robust monotonic change feed/cursor whose semantics remain valid with concurrent transactions; ordinary sequence allocation can commit out of order, so do **not** naively advance a cursor beyond uncommitted earlier writes. Specify RLS indexes, operation retention and pagination in the migration PR.

## Required Phase 1 completed-workout backfill on first account association

An offline guest's Phase 1 workouts have **no outbox entries**. Creating a
sync worker without a backfill would silently omit all workouts logged before
sign-in. Phase 2 must implement and test this explicitly:

1. After authentication, obtain **specific, revocable user consent** to
   associate guest-owned *completed NorthStar* workouts with the current
   account. No automatic assignment on login or account switch.
2. In a local ObjectBox transaction, enumerate eligible completed sessions,
   persist owner association, and enqueue **idempotent portable aggregate
   snapshots** using stable operation IDs derived from the intended account,
   session UUID and associated revision. Exclude drafts, discarded sessions,
   raw health data, plans and other users' records.
3. Make this resumable and duplicate-safe across process death, partial batch
   completion, reconnect, sign-out and sign-in. Prevent the same completed
   session from being assigned to a different account without explicit
   reconciliation. Do not upload until consent and owner-scoped RLS are valid.
4. Cover this in integration tests: old Phase 1 history survives first sync,
   repeated backfill creates no duplicate operations, cloud ACK handling is
   durable, user switches cannot leak data, and existing remote revisions
   trigger conflict resolution rather than overwrite.

**Acceptance:** every consented, eligible completed workout is either durably
queued or explicitly presented as a recoverable failure. Guest history
must never be silently lost from backup eligibility.

## Atomic write algorithm

1. Workout UI -> domain command -> ObjectBox transaction updates session/sets and stores immutable `SyncOutbox` command with stable `operation_id`, snapshot and `expected_revision`.
2. Show locally persisted result regardless of network/login. Guest mutations remain **local only** until explicitly associated with an authenticated owner.
3. Coordinator sends idempotent RPC after authenticated account matches local scope; retries keep same ID.
4. Server transaction authenticates caller and checks RLS/ownership; first check recorded `operation_id` and return identical acknowledgment for replay; otherwise compare `expected_revision`, update aggregate only on match, record operation and assign revision.
5. On conflict, preserve both local pending version and remote snapshot; mark `conflict_needs_resolution`. Provide a user-visible resolution decision; no blind last-write-wins.
6. On durable ACK, advance local baseline/receipt and prune acknowledged outbox safely.
7. On sign-in, app resume, restore or configured interval, pull by server cursor, process tombstones, apply only to records without unresolved local conflict.
8. On sign-out/account switch, stop transfer immediately, partition caches/outbox by owner, warn for unsynced data; never silently upload one user's workouts to another.

### Error states

`queued`, `sending`, `awaiting_ack`, `synced`, `retryable_failure`, `auth_required`, `conflict_needs_resolution`, `permanent_validation_failure`. Restart/reinstall must not permanently hide pending failures.

### Deletions

Delete is a tombstone mutation with expected revision, not a blind physical deletion. Define retention and cursor compaction after cross-device restoration is proven. Deleting a NorthStar cloud backup does **not** delete an independent HealthKit/Health Connect sample; app-owned health sample deletion needs its own user-approved action.

### Data-loss caveat users must see

Initial cloud restore recovers **completed workout history only**, not plans, custom exercise definitions outside embedded snapshots, in-progress sessions, health-platform data, caches or preferences. Warn before uninstall/device switch; do not market as a complete account backup.

## Mandatory integration tests

Two devices edit same revision, retry same operation ID after simulated timeout, concurrent insert, stale deletion vs update, revision monotonicity, restore with interrupted pull, cursor safety across uncommitted transactions, anonymous session account link, cross-user SELECT/INSERT/UPDATE/DELETE/RPC rejected, no forbidden health fields in requests, backoff/recovery after process death, account removal and unsynced warning.
