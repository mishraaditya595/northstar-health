# P2-06 — Reviewed workout conflict recovery (PR #24)

**Implementation candidate — not merged, deployed or device-verified.** See ADR-0006. Completes the missing *functional* P2-06 conflict-resolution slice, subject to independent code/security review and CI. Real signed-JWT multi-device verification and physical-device sign-off remain P2-08 release gates. P2-07 covers broader account/export/deletion settings, not workout conflict recovery.

## Server read contract

Migration `20261027070000_phase2_per_workout_resolution_lookup.sql` adds `public.get_workout_for_resolution(p_workout_id uuid)`. This is an owner-scoped SECURITY INVOKER read endpoint, relying on `workout_records` SELECT RLS; anonymous/public EXECUTE is revoked, authenticated only. Owner is obtained solely from `auth.uid()`, never from a caller parameter. Response fields: `schema_version: 1`, `cursor_epoch`, and `change` (nullable). When present, `change` has the same validated shape as one `get_workout_changes` item: ID, server revision, per-owner change sequence, deleted flag and snapshot (null when deleted). No account IDs or health-platform measurements are returned. This read does not advance the shared restore cursor.

Transport verifies the bound non-anonymous JWT before and after waiting for RPC, and the decoder validates UUID, schema keys, payload and all nested fields through the existing strict restore decoder. A missing row is **not** a tombstone.

## User-driven resolution

The Today notice opens **Workout review** for needs-review and terminal blocked workout operations. Only the signed-in owner's ObjectBox Store is used. The user sees which workout is local/deleted and whether the fresh cloud record is present, deleted or completed, and selects explicitly:

- **Use cloud copy / Accept cloud deletion:** only when the server returns a versioned record. A checked local-revision transaction supersedes terminal operations, materializes the validated server workout or redacts local children and marks a tombstone, updates the remote baseline, then removes the restore skip.
- **Retry this device:** only for eligible completed native phone sessions and **never** against a server tombstone. Supersedes terminal/blocked dependencies, increments the local revision and creates a new immutable completed-upsert operation against the fetched server CAS baseline. An invalid DTO fails and rolls back the entire recovery transaction; no poisoned retry loop is accepted.
- **Complete deletion:** only for a locally deleted workout. When a live remote record exists, supersede the stale conflict/dependency chain, retain the local tombstone and enqueue a new null-payload delete against its current server revision. If the server is already deleted or absent, no extra RPC is created.

A reviewed `superseded` outbox row is terminal and cannot be sent again. The queue and restore importer recognize it as a resolved predecessor. **Pending** requests may already have committed remotely and cannot be superseded by a point lookup; review refuses while one is pending. Owner mismatch, local revision changes, restore epoch mismatch and stale known remote revisions fail without partial writes. The worker can continue processing other workouts while a conflict awaits review.

**Races:** the server may change after the lookup. A new local/deletion operation uses the fetched server revision as an optimistic CAS; another write returns a new conflict for review instead of last-write-wins. A chosen cloud state is rechecked against later restore changes. The importer treats the exact reviewed remote sequence as an already-known replay so the shared cursor advances without a duplicate revision blocker, and applies strictly newer state as usual. Neither user choice rewinds that cursor.

## Validation

- `workout_conflict_lookup.test.sql`: SQL grants, missing/malformed auth, per-owner isolation, missing row, latest revision and tombstone/no-payload checks.
- `workout_conflict_resolution_test.dart`: transactional tests with file-backed ObjectBox for use-cloud, rebase and replay, unknown server row, sticky tombstones, pending-request fail-closed, stale local optimistic revision, owner switch and blocked deletion rebase.
- `workout_restore_transport_test.dart`: point lookup auth before/after HTTP, strict response schema and wrong-ID rejection.
- Existing P2-06 pagination, cursor, skip, delete, dependency and sync widget tests remain mandatory.

**Not tested here:** authenticated hosted Supabase two-device/JWT network E2E; concurrent database request + expired receipt; physical Android/iOS account switch, process kill, app resume, storage upgrades, latency/performance and P2-08 deployment security gates.

## Rollback

Unmount the reviewed recovery entry point and transport, without modifying user workouts. Restrict EXECUTE on `get_workout_for_resolution(uuid)` if necessary; preserve all local outbox, cursor, conflict and tombstone data. Use a forward-only SQL migration for any server changes.
