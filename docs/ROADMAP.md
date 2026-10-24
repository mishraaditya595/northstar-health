# NorthStar implementation roadmap

**Initial foundation (merged PR #2):** Flutter demo screens, Performance V2 reference, adaptive light/dark design, Riverpod, routing, agent rules, ObjectBox package configuration, ADRs and CI. This is not a production health application.

## Production structure/bootstrap (next PR)

Move Flutter to `apps/mobile/` and commit reviewed native Android and iOS runners/lockfile; create independent native `apps/watch_os` and `apps/wear_os` non-recording target scaffolds with build pipelines; define portable `contracts/workout_sync/v1` and test fixtures. **Native watchOS companion embedding and physical device sign/release verification remain separate release gates.** This is not yet a workout tracker.

## Phase 1 — Reliable offline workout logger

Implementation reports and PR scopes live under
[docs/implementation/](implementation/README.md). The foundation and
exercise/plan catalog and backend session lifecycle are implemented;
the active logging UI, rest timer, history/progress and device persistence QA
remain outstanding.

ObjectBox schema and generated model committed; domain models and repository boundary; plan/exercise editor, custom exercise catalog, live sets/reps/weight/RPE, rest timer, progress and session checkpoints; atomic durable write; model-migration and process-death tests. App usable with no account, internet or health permission.

## Phase 2 — Narrow Supabase workout backup

Supabase Auth, session association and secure token storage; row-level security; versioned completed-workout DTO with exercise snapshots; transactional ObjectBox outbox; server-enforced optimistic concurrency/idempotency; pull/restore including tombstones, conflicts and deletion. **Only finished NorthStar logs** are backed up. Custom plans, exercise catalog, in-progress drafts, preferences and health observations remain local initially; clearly state restore limitation.

## Phase 3 — Permission-based platform health reads

Apple HealthKit and Android Health Connect for supported types; distinct per-feature permission prompts, source provenance and timestamps, platform aggregate queries, ephemeral local caches, revocation/unknown/stale behavior, background constraints and supported device matrix. No raw health measurements in Supabase.

## Phase 4 — User-controlled completed-workout export

Opt-in write of one NorthStar-owned workout summary, export receipts and platform-specific retry/reconciliation. Avoid double writing Apple Watch `HKWorkout` or Android sessions; imported workouts stay read-only. Resolve app-owned edits/deletion UX before shipping.

## Phase 5 — Watch companion implementation

Physical-device spikes may begin **earlier in parallel** to avoid late architecture surprises. Record sets/reps/load, rest haptics and native workout sessions under watchOS HealthKit / Wear OS Health Services; local offline journal, phone pairing, reconnection ACK and app-background recovery. Validate Flutter UI on Wear OS vs Compose and FlutterWatch on watchOS vs SwiftUI; no production dependency on experimental engine without real tests.

## Diagnostics/privacy cross-cutting gate

Introduce Firebase Crashlytics/Analytics only after privacy disclosure, separate collection controls, explicit native defaults-off configuration and sensitive-payload redaction tests. Add security tests for Supabase RLS, no health cache uploads, data deletion and account boundaries. Run profiling on low-end Android/iPhone/tablet and both watches.

## Deferred product choices

- Adding cloud backup for custom plans/templates (current initial trade-off: they are lost on reinstall).
- Cross-phone recovery of in-progress sessions.
- Platform-workout post-export correction/deletion policy.
- Health cache time-to-live tuning, secure backup exclusions, encryption requirement, server tombstone retention.
- More direct wearable provider APIs and beyond-MVP recovery/readiness calculations (none shipped without validity review).
