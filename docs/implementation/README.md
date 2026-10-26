# NorthStar implementation notes

The [roadmap](../ROADMAP.md) defines product milestones. Each note records actual behavior, data ownership, QA gaps and PR evidence rather than replacing the ADRs.

## Phase 1 — local workout logger

- [ObjectBox foundation](phase-1/objectbox-foundation.md) — session/set durability and revisions (PR #5).
- [Exercise catalog and plans](phase-1/exercise-catalog-and-plans.md) — local exercises and atomic plans (PR #7).
- [Plan editor hardening](phase-1/plan-editor-hardening.md) — follow-up to PR #7.
- [Live workout engine](phase-1/live-workout-engine.md) — atomic quick/plan start and recovery.
- [Active workout logger and rest timer](phase-1/active-workout-logger.md) — saved sets and resumable sessions (PR #10).
- [Workout history and progress](phase-1/workout-history-progress.md) — completed history, trends and details (PR #11).

## Phase 2 — mandatory accounts and automatic sync

- [P2-01 Supabase backend foundation and review remediation](phase-2/p2-01-supabase-foundation.md) — PR #13 (merged), completed-only phone workout RPC, migration history, tests and outstanding release gates.

- [P2-02 Mandatory Flutter authentication and owner-bound offline storage](phase-2/p2-02-account-authentication.md) — PR #14 (merged), account gate, secure email code auth, isolated ObjectBox directories and account sign-out.

- [P2-03 Durable ObjectBox outbox and auth backup-paused state](phase-2/p2-03-durable-outbox.md) — PR #15 (**merged**), completed phone workout snapshot queue and schema upgrade tests.

- [P2-04 Authenticated Supabase upload worker](phase-2/p2-04-authenticated-uploader.md) — PR #16 (**merged**), foreground automatic uploader, resilient retries, CAS/idempotency, completed-only backfill and account guard; restore and conflict UX remain outstanding.

- [P2-05 Server progress aggregation](phase-2/p2-05-server-progress.md) — PR #17 (**draft/in progress**), server-derived day-level workout aggregates, nullable weighted-volume semantics, authenticated read API and SQL regressions. No Flutter UI / raw physiological data.

Authoritative policy: [ADR-0003](../adr/0003-data-cloud-health.md) **as superseded for auth/cloud workout scope** by [ADR-0005](../adr/0005-mandatory-auth-and-workout-sync.md), [ObjectBox](../OBJECTBOX.md), and [Cloud Sync](../CLOUD_SYNC.md).
