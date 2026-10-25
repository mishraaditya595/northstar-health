# ADR-0003 — Local data, cloud backup, health integrations and diagnostics

**Supersession notice (2026-10-25):** [ADR-0005](0005-mandatory-auth-and-workout-sync.md) requires accounts for new users and extends workout cloud sync to phone lifecycle snapshots (active, paused, completed, discarded). Completed-only and optional-auth passages below document the historical decision and are **not current policy**. Health-platform prohibitions and other data boundaries remain unchanged.

**Status:** Accepted direction for initial implementation; specified product and release gates remain open  
**Date:** 2026-10-23  
**Source:** User-supplied *NorthStar Health — Local Data, Cloud Backup & Health Platform Integration* (ADR-001, 23 October 2026). This repository numbers it ADR-0003 to avoid collisions with ADR-0001 (Flutter foundation) and ADR-0002 (watch architecture).

## Executive decision

NorthStar is an offline-first workout tracker and a permission-based viewer of health-platform measurements.

- **ObjectBox** owns the mobile app's durable, user-created workout plans/logs, local in-progress state, sync queue, export receipts and short-lived permitted health *caches*.
- **Supabase Auth + PostgreSQL** syncs *NorthStar phone workout lifecycle aggregates and the minimum exercise/set snapshots needed to interpret them* (ADR-0005 supersession). Never upload platform-derived heart rate, HRV, sleep, steps, SpO₂, GPS tracks or health dashboard caches. **ObjectBox files are never uploaded**: use portable DTOs and domain UUIDs.
- **HealthKit on Apple platforms / Health Connect on Android phones** supply authorized physiological measurements and imported workout summaries. No universal third-party wearable coverage is promised.
- **WorkoutHealthExport** may write one summary of a *completed, NorthStar-owned* workout into the platform's supported workout/exercise-session format with separate user permission. Do not write individual reps/sets as health measurements, manufacture calories, or re-export third-party workouts.
- **Firebase Crashlytics and Analytics** are chosen *future* diagnostics providers. Collection defaults off, separate consent and hard data minimization are mandatory before the SDKs are activated. No workout values, notes or raw health samples in events, custom keys, breadcrumbs, crash attachments or logs.
- Watch companions keep their own offline journal and use versioned replay-safe transfers to the phone. Native session engines capture sensor/workout state even when watch UI is backgrounded.

This is a decision about boundaries and implementation order, **not a claim that those integrations currently run in the Flutter demo**.

## Ownership and backup matrix

| Data | Authority | Mobile ObjectBox | Supabase | HealthKit / Health Connect |
| --- | --- | --- | --- | --- |
| NorthStar completed session + exercise snapshots | NorthStar workout record | Durable | Backed up | Optional summary export only |
| Set logs, load, reps, RPE/RIR, rest, user notes | NorthStar workout record | Durable | Backed up | Not portable as individual sets |
| In-progress workout and recovery checkpoint | Originating NorthStar device | Durable | **Active set/session snapshot only**, not rest/recovery checkpoint state (ADR-0005) | Never export draft |
| Custom plans and exercise catalog | NorthStar user/device | Durable | **Local only initially** | No |
| HR, resting HR, HRV, sleep, steps, distance, energy, SpO₂ | Contributing health platform | Bounded authorized cache | **Never** | Read only initially |
| Derived progress/health analytics | Derived on device | Recompute or temporary cache | No independent backup | Read source values locally |
| Access/refresh tokens | Auth secure credential store | **Never** | Supabase Auth | No |
| Cloud/watch outbox and health export receipt | Originating app/device | Durable metadata | Not separately backed up | External record linkage where supported |

**Confirmed product trade-off:** a fresh installation can restore completed workout logs but not custom plans/templates in the initial backup release. Show this clearly before users rely on cloud restoration. Expanding plan/catalog backup requires a new scope/consent decision; design schemas with stable IDs so it is additive.

## Cloud consistency: adopted MVP strategy

Choose **one logical versioned workout aggregate per NorthStar phone session** across its lifecycle rather than independently synchronizing every set row (ADR-0005). The proposed first Supabase schema is a row per workout `(user_id, workout_id, revision, payload_jsonb, updated_at, deleted_at)`, with exercise/set snapshots in a size-bounded versioned payload. The canonical ObjectBox entities remain separate, mapped into a portable DTO. Later normalization is possible without changing external UUIDs or revision semantics.

- Client mutation stores its data and outbox command in **one ObjectBox transaction**.
- Server operations include `operation_id`, `workout_id`, `expected_revision`, versioned DTO, and authenticated principal.
- Use a single Postgres transaction / audited RPC for compare-and-set: check `auth.uid()` ownership, validate payload/size/version, dedupe `(user_id, operation_id)`, and only update if `revision = expected_revision`; return assigned authoritative revision and acknowledgment. Never rely on client-side revision comparison for conflict safety.
- A stale revision returns a **conflict**, not a silent overwrite. Preserve the unsent local edit and remote version for review/explicit merge. Do not implement automatic last-write-wins for simultaneous plan/workout edits.
- Pull changes with a **server-owned monotonic cursor/sequence**, not client timestamps alone; maintain tombstones and deletion reconciliation across reinstalls; choose retention before release. Avoid a cursor that skips concurrent transactions.
- Sender removes/marks outbox entries only after the server's **durable** acknowledgment. Transport timeouts are ambiguous: retry same operation ID, do not assign a new one.
- Account scoped ownership with RLS for all reads/writes. Do not ship `service_role` credentials. Any privileged RPC must enforce `auth.uid()`, ownership, explicit search_path and least privilege; run malicious cross-user tests.
- Guest workouts never silently attach to a newly logged-in person's account. Require explicit account association; pause/partition queues and protect unsynced data on logout, account switch and deletion.
- Encrypt transport; define local OS backup and key handling and server data-deletion policy before enabling sync.

See [Cloud sync specification](../CLOUD_SYNC.md) for state machines, acceptance tests and unresolved release details.

## Distinct health pipelines

1. **PlatformHealthRead:** permissioned HealthKit/Health Connect reads -> source-aware aggregation -> bounded, expiring on-device cache. Respect actual availability, sample provenance, partial permissions, platform dedup rules, and cache invalidation on revocation.
2. **WorkoutHealthExport:** only NorthStar-owned *completed* sessions -> supported platform workout/exercise-session summary with explicit write permission. Never export imported platform workouts or copied sensor samples.
3. **WorkoutCloudSync:** ObjectBox workout aggregate + outbox <-> Supabase backup/restore. No health cache or raw sensor payloads.

These pipelines **must not trigger each other recursively**. Their IDs, permissions and failure/reconciliation states are independent.

For Apple Watch sessions already persisted as `HKWorkout`, phone records the source/export receipt and **does not write another `HKWorkout`**. For Wear OS, designate one platform writer (normally the phone) for a given NorthStar session. Preserve stable platform IDs; do not mistake Apple external UUID metadata for guaranteed deduplication. After ambiguous crashes, query/reconcile app-owned records before retrying exports.

See [Health data and export policy](../HEALTH_DATA.md).

## Security, diagnostics and data rights

Treat *workout history and free-text notes as sensitive*, even though cloud data excludes raw platform vitals. Default automatic telemetry collection **off at native SDK configuration**; no SDK gets initialized for collection until separately documented privacy policy, transparent consent, retention, opt-out/revocation, audit/test, and sanitization of crash contexts. Crashlytics and Analytics consent controls are separate; allowlist event names and static non-sensitive parameters only.

ObjectBox on-device file-level encryption is **not presumed**. Evaluate iOS data protection, Android private storage/backup exclusion, account isolation and credential storage. Reopen database choice if app-level encryption becomes a hard requirement. Never store Supabase tokens in ObjectBox.

Review platform store policies, data safety disclosures, permissions, deletion and local/cloud retention for actual shipped functionality. This ADR is not a legal compliance guarantee.

## Deferred / explicit decisions

- No custom plan backup in initial scope; separately prioritize optional inclusion later.
- Full in-progress UI/checkpoint recovery across phones is deferred although active-session sets synchronize under ADR-0005. Watch/phone local recovery is **required**.
- Whether export is prompted at first completed workout vs later settings is a UX decision; default no export until permission and purpose explained.
- Define retention/deletion tombstone periods and account-switch UI before production.
- Define post-export update/delete behavior for immutable HealthKit workouts; no silent duplicate writes.
- Validate Health Connect historical access, native platform capabilities, OS backup exclusions, privacy disclosures and performance on real devices.
- Confirm long-term compatibility of smartwatch frameworks separately under ADR-0002.

## Reconciliation with earlier ADRs

This ADR **supersedes ADR-0001 only** for backend scope and diagnostics provider; its optional-account and completed-only sync assumptions were subsequently superseded by ADR-0005: Supabase + Firebase replace the earlier “none initially / Sentry candidate” direction. ADR-0001 remains authoritative for Flutter/Riverpod/go_router/adaptive UI. ADR-0002 remains authoritative for watch-native session engines. ObjectBox remains the chosen local store.

## Release acceptance

Test durable offline logging and recovery; prior-version ObjectBox model migration; 2-phone revision conflict and retry after timeout; RLS negative tests; multi-user/logout boundaries; health permission revoke/cache purge; HealthKit/Health Connect export dedup after interrupted write; watch disconnect event replay; consent-disabled Firebase produces **no** diagnostic/analytics upload; low-end Android size/latency and physical-watch background continuity.
