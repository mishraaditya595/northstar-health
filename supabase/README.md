# NorthStar Supabase — development backend

**Status:** Phase 2 P2-01 database/RPC migrations are applied to the **development** Supabase project. No mobile authentication/sync worker is yet shipped; PR #13 is under review and is not production-ready. See [ADR-0005](../docs/adr/0005-mandatory-auth-and-workout-sync.md) and [Cloud Sync Contract](../docs/CLOUD_SYNC.md).

Seven ordered migrations under `supabase/migrations/` create and then harden `workout_records`, `workout_sync_operations`, `northstar_private.workout_owner_cursors` and the authenticated `sync_workout` RPC. The initial migration is retained because it was applied to the dev instance. The hardening adds strict required-field checks and typed values, hashed 90-day receipts, per-owner change cursors, and conditional revision updates. The third migration fixes a validator special-form spelling error. The fourth adds owner-triggered expired-receipt pruning and safely revokes public execution of the hosted-only RLS event-trigger function if present; the fifth and sixth close numeric, UUID and tombstone bugs; the seventh restricts sync to completed workouts (ADR-0005).

`supabase/tests/workout_sync.test.sql` is a rolled-back, synthetic pgTAP suite (64 TAP-visible assertions) covering account boundaries, JSON validation, replay, deletion and processing. The `.github/workflows/supabase_sql.yml` job starts a clean local database, replays migrations, and runs `supabase test db`. Run the same commands locally or in CI and record its result in the PR before merge. Real two-connection concurrency tests and release/privacy gates remain open.

Do not commit private or service-role keys, database credentials, bearer tokens, real workout records, raw platform health data, or full ObjectBox database files. Flutter may use a public project URL and publishable key with authenticated sessions; only the backend controls privileged storage and server computations.

**Rollback:** Do not delete workout tables. Revoke authenticated RPC EXECUTE to halt cloud writes, preserve ObjectBox queues, then deploy a corrective migration. Do not replay an older vulnerable function over newer production migrations.
