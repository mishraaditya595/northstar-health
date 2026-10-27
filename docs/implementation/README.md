# NorthStar implementation notes

The [roadmap](../ROADMAP.md) tracks milestone state. These notes describe source behavior, data ownership, PR evidence and outstanding QA; they are not production approval. **As of 27 October 2026, P2-01–P2-07 are merged in source; P2-08 release validation has not passed.**

## Phase 1 — durable offline workout logger

- [ObjectBox foundation](phase-1/objectbox-foundation.md) — session/set transactions and revisions (#5).
- [Exercise catalog and plans](phase-1/exercise-catalog-and-plans.md) and [plan hardening](phase-1/plan-editor-hardening.md) — local definitions and atomic plans (#7).
- [Live workout engine](phase-1/live-workout-engine.md) and [active logger/rest timer](phase-1/active-workout-logger.md) — recovery, saved sets and rest timers (#10).
- [Workout history and progress](phase-1/workout-history-progress.md) — completed history, trends and details (#11).

## Phase 2 — authenticated completed-workout sync and data rights

- [P2-01 Supabase foundation](phase-2/p2-01-supabase-foundation.md) — completed-only owner-scoped sync RPC and migration/security tests (#13).
- [P2-02 Mandatory account sign-in](phase-2/p2-02-account-authentication.md) — email-code Auth and owner-isolated local partitions (#14).
- [P2-03 Transactional completed-workout outbox](phase-2/p2-03-durable-outbox.md) — durable local queue and upgrade regressions (#15).
- [P2-04 Authenticated foreground uploader](phase-2/p2-04-authenticated-uploader.md) — account-matched retries, revisions and idempotency (#16).
- [P2-05 Server progress](phase-2/p2-05-server-progress.md) — day-level server aggregates with explicit missing-data semantics (#17).
- [P2-06 Restore/change feed](phase-2/p2-06-restore-and-conflicts.md), [transport](phase-2/p2-06-mobile-restore-transport.md), [atomic ObjectBox importer](phase-2/p2-06-mobile-objectbox-importer.md), and [serialized foreground coordinator](phase-2/p2-06-foreground-restore-coordinator.md) — rollback epoch, cursor and transaction safety (#18–#22).
- [P2-06 Queue fairness and dependency ordering](phase-2/p2-06-fair-upload-queue.md) — blocked revision handling (#23).
- [P2-06 Workout tombstones](phase-2/p2-06-completed-workout-deletion.md) and [reviewed conflict resolution](phase-2/p2-06-reviewed-conflict-resolution.md) — deletion and user-controlled recovery (#24).
- [P2-07 Account/sync status, JSON cloud-history export and permanent account deletion](phase-2/p2-07-account-status-data-rights.md) — #25, #27 and #29 merged. Uncertain deletion retains files locked unless the user independently chooses to erase them; [ADR-0007](../adr/0007-account-deletion-recovery-exit-choices.md) preserves both exit choices.
- [P2-08 export/device verification matrix](phase-2/p2-08-workout-export-release-validation.md) — **not run**, alongside hosted signed-JWT/RLS, two-device, Auth-deletion and production rollout gates in [RELEASE.md](../RELEASE.md).

**Policy and operational guides:** [ADR-0003](../adr/0003-data-cloud-health.md) (superseded for auth/cloud scope by [ADR-0005](../adr/0005-mandatory-auth-and-workout-sync.md)), [ObjectBox](../OBJECTBOX.md), [Cloud Sync](../CLOUD_SYNC.md), [account deletion runbook](../../supabase/ACCOUNT_DELETION_RUNBOOK.md), and [Supabase restore runbook](../../supabase/RESTORE_RUNBOOK.md). "Merged" does not imply hosted deployment, real-device verification or store release.
