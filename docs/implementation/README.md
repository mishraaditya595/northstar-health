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

- [P2-05 Server progress aggregation](phase-2/p2-05-server-progress.md) — PR #17 (**merged 2026-10-26**), server-derived day-level workout aggregates, nullable weighted-volume semantics, authenticated read API and SQL regressions. No Flutter UI / raw physiological data.

- [P2-06 Restore feed and conflict handling](phase-2/p2-06-restore-and-conflicts.md) — PR #18 **merged**, owner-isolated paginated server change feed with a rollback epoch and pgTAP tests. Safe mobile import, reconciliation, deletion and conflict UX remain open.

- [P2-06 Flutter restore transport and strict decoder](phase-2/p2-06-mobile-restore-transport.md) — PR #19 (**merged**), authenticated read-only RPC, validated epoch/pagination and completed workout DTOs; PR #22 merged and connects them to the foreground worker.

Authoritative policy: [ADR-0003](../adr/0003-data-cloud-health.md) **as superseded for auth/cloud workout scope** by [ADR-0005](../adr/0005-mandatory-auth-and-workout-sync.md), [ObjectBox](../OBJECTBOX.md), and [Cloud Sync](../CLOUD_SYNC.md).

- [P2-06 Transactional ObjectBox restore importer](phase-2/p2-06-mobile-objectbox-importer.md) — PR #20 (**merged**), versioned owner cursor and remote tombstones, atomic page import and host-native schema/restart/rollback tests; foreground pull is merged in PR #22; conflict recovery remains outstanding.

- [P2-06 Foreground restore coordinator](phase-2/p2-06-foreground-restore-coordinator.md) — PR #22 (**merged**), foreground serialized upload/pull, paged restore, epoch recovery, skip records and host-native tests; not yet released.

- [P2-06 Fair upload queue and durable dependencies](phase-2/p2-06-fair-upload-queue.md) — PR #23 (**draft**), bounded ObjectBox-window scan beyond 500 and persisted dependency-paused upload revisions; independent review/device tests outstanding.
