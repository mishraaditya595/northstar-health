# NorthStar authenticated completed-workout synchronization

**Policy:** [ADR-0005](adr/0005-mandatory-auth-and-workout-sync.md) (accepted by the owner 2026-10-25) supersedes ADR-0003's optional-login and guest assumptions and keeps its completed-only backup scope. This is a *new product decision*, not an observation about the shipping Flutter app.

**Implementation status:** P2-01 through P2-03 are merged. P2-04 (PR #16, **draft under review**) wires the local completed-only outbox to the authenticated Supabase RPC with poison-record-safe backfill, future-clock-safe durable attempts, exponential retry, immutable operation UUID, server CAS acknowledgements and account-scoped historical completion backfill. Upload occurs **only while a signed-in account app is active/foregrounded**; there is no promise of terminated/background delivery. Known P2-06/P2-07 gaps: later revisions stay pending behind blocked/conflicting predecessors, and first-500 pending scans can starve other eligible rows until fair pagination is implemented. Restoring to a new device, tombstones/deletions, conflict-resolution UX, export/account deletion and device release QA remain outstanding.

## Data classification and account gating

Everyone must register/sign in before using workout features (no guest mode); first authentication requires internet. A securely authenticated account may continue offline, save locally and enqueue changes until the network and auth session can resume. Supabase Auth anonymous accounts are not valid NorthStar accounts.

Cloud accepts *versioned NorthStar-authored phone workouts* only in `completed` state (finished by the user), and deletion tombstones. In-progress, paused and discarded sessions are rejected by the RPC and the table constraint. One aggregate contains session metadata, exercise name/muscle/equipment snapshots, and per-set position/status/type/reps/gram load/unit/RPE/completion time. **This is not a full active-workout checkpoint or plan backup.**

**Never upload:** HealthKit/Health Connect physiological data (HR, HRV, sleep, steps, SpO₂, GPS, etc), imported workouts, raw watch sensor streams, full ObjectBox databases, platform access tokens, app telemetry or device secrets; local recovery timers and editor state; custom plans/templates/catalogs or preferences. Any expansion to exercise notes/durations/RIR requires an explicit versioned DTO change plus privacy/tests.

## Real development schema (P2-01)

- `public.workout_records`: account/workout composite key; one versioned JSONB aggregate; `status`, deletion tombstone, server revision, per-owner `server_change_seq`, and server-derived `completed_working_sets`, `loaded_working_sets`, `loaded_volume_gram_reps`.
- `public.workout_sync_operations`: idempotency receipt keyed by `(user_id,operation_id)`. Holds `request_sha256` (**not the workout payload**), revision and cursor receipt, `committed_at`, `expires_at` (90-day policy).
- `northstar_private.workout_owner_cursors`: per-owner monotonic counter, transactionally advanced. It is not an exposed Data API table.
- `public.sync_workout(operation_id,workout_id,expected_revision,action,payload)`: SECURITY INVOKER wrapper calling an audited private SECURITY DEFINER implementation. Anonymous callers have no EXECUTE grant. Direct client INSERT/UPDATE/DELETE on tables is revoked; owner-only SELECT on records uses RLS. The function derives account identity from `auth.uid()`, not user-supplied JSON.

Migration names/versions correspond to the development project migration history: `20261025060300_phase2_workout_sync_foundation.sql`, `20261025063753_phase2_workout_sync_hardening.sql`, `20261025063912_phase2_validation_coalesce_fix.sql`, `20261025064908_phase2_receipt_expiry_and_security_cleanup.sql`, `20261025070923_phase2_identity_and_tombstone_guards.sql`, `20261025071009_phase2_tombstone_delete_retry_guard.sql`, `20261025090000_phase2_completed_only_scope.sql`. The original migration is retained and repaired by subsequent migrations; *do not rewrite already applied migration history*. Replay all seven in order on clean test databases.

## Disclosure and data rights

The privacy notice and signup flow disclose that finished workouts are backed up automatically. Approved data policy: workout records last until deletion/account closure; tombstones last for the account lifetime; hash-only receipts expire after 90 days. The mobile app must support authenticated workout JSON export and in-app account deletion, including unsynced-data warnings and secure local cleanup. **Approved in ADR-0005 but not yet implemented.**

## Validation and replay

All required object keys must be present with correct JSON types: workout (version, ID, origin, status, name, start, offset, exercises), exercise (ID, name, position, sets), and set (ID, position, kind, status, unit); completed workouts require completion timestamps and performed sets require repetitions + timestamps. Additional fields are **rejected**. IDs must parse as UUIDs, times as ISO-8601 timestamptz, numerical values have bounded ranges and proper JSON number types. Duplicated exercise/set IDs, external origin and health samples are rejected. Maximum aggregate 64 KiB, 120 exercises, 300 sets per exercise.

Validation happens **before** the owner transaction lock and **before** checking remote revisions: a stale *invalid* write is a validation error, not a conflict. Per-user advisory lock plus server-side revision compare-and-swap preserve conflict behavior. A new row uses plain INSERT; an existing row uses conditional UPDATE `WHERE server_revision=expected_revision`. No last-write-wins or overwrite on revision mismatch.

Replay compares SHA-256 of a canonical JSON request tuple (workout ID, expected revision, action, payload) against the stored receipt. A repeated matching operation returns the original acknowledgement; a reused operation ID with different content is a validation error. Response keys are `result` (`applied|conflict`), `revision`, `change_seq`, `replay`, `processing` (`processed|not_applied`). **Never assume the network response means the phone outbox was durably dequeued**; persist the receipt first.

## Processing and missing values

For *completed* workouts only, the server calculates completed working sets, loaded working sets and loaded volume (positive recorded grams times recorded reps). Warmups, non-performed sets, missing/zero loads and unknown states are excluded from loaded volume. A known workout with **no positive recorded weight** stores NULL loaded volume, never a fictional zero. Processing is synchronous in P2-01; no asynchronous worker is implemented yet.

## Retention, deletion, restore and backward compatibility

- A delete writes a tombstone and nulls the primary payload. The receipt stores only a hash. Hash receipts expire after **90 days**. The next authenticated sync opportunistically deletes that owner's expired receipts; `northstar_private.prune_expired_workout_receipts()` also supports a privileged full purge. **Scheduling/monitoring that full purge for inactive accounts remains a release blocker**. When an expired operation is retried, it may return a revision conflict and require reconciliation; never silently overwrite.
- Deleted workout UUIDs are sticky tombstones: a new upsert is rejected with an explicit `reason: deleted` conflict, while a repeated explicit delete is allowed; exact replay remains idempotent. Tombstones are kept until the account is deleted (ADR-0005). Cursor-safe restores still need pagination testing. Do not purge tombstones as if they were receipts.
- There is no guest mode and no guest data to import. Prevent cross-user attachment on logout/switch.
- Phone outbox, account-bound local stores, offline JWT lifecycle, last-server-revision tracking, resume and conflict-resolution UI are future PRs. **Current server existence does not mean cloud sync is working in Flutter.**
- Only completed workout history can be restored; unfinished sessions never leave the device. Plans, catalog and preferences are not restored.

## Validation, security and rollback

`supabase/tests/workout_sync.test.sql` emits 64 pgTAP assertions with `plan(64)` and standard TAP output, including rejection of in-progress/paused/discarded workouts, RPE 10.5, case-insensitive UUID uniqueness and permanent tombstone protection. It contains synthetic tests for missing fields at each depth, replay and hash-only retention, malformed numeric/timestamp inputs, denial of table writes, owner separation and tombstones. Run `supabase test db` on a **clean** local/CI Supabase stack before merge; the development Supabase SQL execution is additional evidence, not a replacement for clean migration replay or multi-connection concurrency testing.

Always run Supabase security/performance advisors. The fourth migration revoked unauthorized public invocation of the existing `rls_auto_enable()` event-trigger function. Remaining INFO notices for policy-less RLS tables are intentionally deny-all. Privileged/secret API keys, access tokens and database passwords must **never** enter Git or mobile packages; a publishable key can be embedded only with RLS and authenticated server authorization.

**Emergency rollback:** revoke authenticated EXECUTE on the public sync RPC and disable upload retries without deleting server workouts or local outbox. Re-enable only after a tested corrective migration, not by downgrading to the vulnerable original RPC. Do not drop tables containing live user data. Remote migration history is immutable; address schema fixes via additive follow-up migrations.
