# NorthStar agent operating agreement

Applies to **all AI coding, design, test and review agents**. Read `README.md`, `docs/ARCHITECTURE.md`, `docs/DESIGN_SYSTEM.md`, `docs/adr/0003-data-cloud-health.md`, `docs/OBJECTBOX.md`, `docs/CLOUD_SYNC.md`, `docs/HEALTH_DATA.md`, `docs/SYNC_PROTOCOL.md`, `docs/WEARABLES.md`, `docs/FIREBASE_PRIVACY.md`, `docs/REVIEW_GUIDE.md` before changes.

## Agent workflow

1. Inspect current implementation and tests. Write a focused plan describing the actual data owner, device behavior, security/permissions, recovery tests and changed files.
2. Work in a task branch; keep PRs small, reproducible and independently reviewable. Do not self-approve, merge, override a check or claim CI ran when it did not.
3. Keep Dart feature-first: UI renders Riverpod state, go_router handles routes, repositories and mappers isolate platform APIs/ObjectBox/Supabase DTOs/Firebase. No network/storage SDK use directly in widgets.
4. Use `prototypes/performance-v2/` and `docs/DESIGN_SYSTEM.md` as visual authority. Support light/dark, phone and tablet split screen, text scaling, accessibility, safe areas, reduced motion and low-end Android.
5. Test loading, empty, stale, denied, failure/retry, offline, process death, duplicate and account separation. Use fictional or fully synthetic test health data, never real user exports in Git.
6. Run `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`; include runtime and actual device tests for native/persistence/watch integration. Record all unrun checks and risks.

## Data ownership hard rules

- **ObjectBox phone:** durable NorthStar workouts, exercises, sets, plans, in-progress checkpoints, outbox, export receipts; only temporary, authorized health caches.
- **Supabase:** authenticated backup/restore of **completed NorthStar workout history** and essential exercise snapshots only. No full local database uploads. Custom plans/templates, catalog, drafts, health caches, imported platform workouts and platform vitals are **not** initially backed up.
- **HealthKit/Health Connect:** source of user-authorized physiological measurements. Only app-owned completed workout **summaries** may be exported, with separate write permission, platform record identity and dedup receipts. Never fabricate calories/readiness or show missing as zero.
- **Firebase Crashlytics/Analytics:** decided provider but disabled/unconfigured until reviewed consent/redaction. Never collect user notes, health measurements, workout values, tokens, source/device IDs or raw API errors. Sentry is no longer the selected solution.
- **Authentication/identity:** don't keep tokens in ObjectBox; no service_role keys; account-scoped RLS; never silently attach guest workouts to the wrong signed-in account.

## Durable write and conflict contract

- Local workout edit and `SyncOutbox` entry commit atomically. Show saved only after local commit. Cloud retries keep the same operation UUID, use **server-enforced expected revision compare-and-set**, preserve conflict versions and use durable ACK before dequeue.
- Watch logs its own set and event durably, phone records set+inbox receipt atomically, phone ACKs, then independently attempts Supabase backup. ACK from phone != cloud backup.
- WatchOS: native HealthKit workout engine, watch-origin `HKWorkout` saved once and never duplicated by phone. Wear OS: native Health Services session, one chosen platform export writer. UI toolkit is under device-test evaluation.
- Permission revocation invalidates cached health reads. Platform health data can **never** flow into cloud workout backups or Firebase telemetry.
- Respect ObjectBox stable model UIDs; commit generated code and `lib/objectbox-model.json`; test migrations with old databases.

## Review completion checklist

**Why / changed behavior / data ownership / privacy / offline+sync state / UI light+dark+tablet evidence / tests actually run / failure and rollback / deferred functionality**. A reviewer challenges serialization contracts, migration, RLS and replays separately. Changes to policies, provider choices, backup scope or watch ownership need a numbered ADR.
