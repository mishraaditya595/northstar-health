# Phase 2 / P2-01 — Supabase workout sync foundation

**Review state:** PR #13; ADR-0005 accepted by the owner. Merge is a human action.  
**Policy:** [ADR-0005](../../adr/0005-mandatory-auth-and-workout-sync.md) (mandatory accounts, no guest mode, completed-workout sync).  
**Backend environment:** Connected *development* Supabase project, not production.

## Actual implementation

Seven migrations are committed in `supabase/migrations/`. The first six were applied in the development Supabase project; the seventh is **not yet applied there**:

1. `20261025060300_phase2_workout_sync_foundation.sql` — initial account-scoped records, receipts and RPC. **Historical, had reviewer-found validation/CAS defects, never deploy by itself.**
2. `20261025063753_phase2_workout_sync_hardening.sql` — strict required-key and type checks; timestamps parsed and chronology validated; hashes instead of raw receipts; 90-day expiry and private purge function; per-owner cursors; owner-only RLS reads and no direct client writes; private privileged RPC behind invoker wrapper; conditional revision UPDATE and plain INSERT; uniform replay/conflict response fields.
3. `20261025063912_phase2_validation_coalesce_fix.sql` — correct PostgreSQL `COALESCE` spelling, discovered by a live synthetic RPC smoke test.
4. `20261025064908_phase2_receipt_expiry_and_security_cleanup.sql` — prune expired owner receipts during authenticated sync; add expiry index; remove redundant cursor index and conditionally revoke publicly executable hosted-only RLS helper if it exists.
5. `20261025070923_phase2_identity_and_tombstone_guards.sql` — reject out-of-range RPE, case-insensitive duplicate UUIDs, and implicit tombstone revival.
6. `20261025071009_phase2_tombstone_delete_retry_guard.sql` — permit explicit repeat deletes without allowing upsert resurrection.
7. `20261025090000_phase2_completed_only_scope.sql` — ADR-0005 scope: accept only `completed` workouts in the RPC and table constraint; remove earlier non-completed synthetic dev rows and their receipts.

Everyone must authenticate initially (no guest mode); offline logging is still allowed afterwards for the securely bound account. Workouts upload automatically in later Flutter PRs. The server accepts only `completed` NorthStar phone workouts and **not** in-progress, paused or discarded sessions, plan templates, editor/rest checkpoints, external workouts, personal health signals, imported device samples or platform identifiers. Completed metrics alone are server-processed; missing loaded volume stays NULL.

## Verification evidence

- Live development SQL migrations returned success and their versions were read back using Supabase migration listing.
- One synthetic authenticated RPC saved a completed workout with a valid revision, cursor and processing acknowledgement inside `BEGIN/ROLLBACK`.
- `supabase/tests/workout_sync.test.sql` has **64** pgTAP assertions using `select plan(64)` and direct TAP result emission for `supabase test db`. They ran against the connected development database inside a rolled-back SQL transaction. No synthetic users or workouts were retained.
- The suite covers required key omissions at every level, forbidden origin/extras, string and overflowing numeric values, timestamps, exercise/set identity duplication, ownership isolation, direct-DML denial, stable replay hashing, conflict-before/after validation, deletion tombstones, per-owner cursors and missing/zero loaded set handling.
- Latest security advisor reports **INFO only** for the two tables with RLS and no client policies (intentional deny). The fourth migration revoked the pre-existing public `rls_auto_enable()` execution grant; no publicly executable SECURITY DEFINER functions are reported.
- The old global sequence and its unique index were replaced; hashed receipts never retain deleted raw workout snapshots.

## Remaining merge/release gates

- **Clean-project test:** Run all seven committed migrations on a pristine database and execute `supabase test db` in CI. This environment lacked a local Supabase CLI/Docker/psql; the remote SQL execution does not establish fresh-migration reproducibility.
- **Concurrency:** Two independent database connections writing the same workout/owner, plus different accounts concurrently, must demonstrate CAS correctness and gap-free per-user change cursors under commit ordering.
- **Retention:** Owner-specific pruning now occurs during sync and is covered by pgTAP; verify external 90-day purge scheduling/monitoring for inactive users and replay behavior after expiry.
- **RLS:** Run additional authenticated cross-user API tests outside the DB simulation (real JWTs) and re-review private SECURITY DEFINER permissions/search_path.
- **Mobile:** P2-02+ are required for actual sign-in, ObjectBox account ownership/outbox, retry, conflict UX and restoration and device release verification.
- **Privacy and policy:** ADR-0005 is **accepted** by the owner. Before release implement the signup disclosure, account-lifetime tombstone retention, authenticated data export and in-app account deletion.
- **CI:** New `.github/workflows/supabase_sql.yml` runs clean local database initialization, reset/migration replay and `supabase test db`. Do not mark this gate verified until that GitHub check succeeds.

## Rollback

No blind DOWN migration or destructive schema downgrade: even the initial vulnerable function exists only in migration history. For emergency safety, revoke authenticated EXECUTE on `public.sync_workout(uuid,uuid,bigint,text,jsonb)`; keep the local outbox and server records intact, patch via a new migration, test, and then restore access. Never drop the records table or migrate user-owned data backwards without a fully tested export and restore plan.
