# NorthStar implementation roadmap

**Initial foundation (merged PR #2):** Flutter demo screens, Performance V2 reference, adaptive light/dark design, Riverpod, routing, agent rules, ObjectBox package configuration, ADRs and CI. This is not a production health application.

## Production structure/bootstrap (next PR)

Move Flutter to `apps/mobile/` and commit reviewed native Android and iOS runners/lockfile; create independent native `apps/watch_os` and `apps/wear_os` non-recording target scaffolds with build pipelines; define portable `contracts/workout_sync/v1` and test fixtures. **Native watchOS companion embedding and physical device sign/release verification remain separate release gates.** This is not yet a workout tracker.

## Phase 1 — Reliable offline workout logger

Implementation reports and PR scopes live under
[docs/implementation/](implementation/README.md). The foundation and
exercise/plan catalog and local session lifecycle engine (no UI) are implemented;
the active logging UI and rest timer have been merged in PR #10;
completed workout history/progress is under review in PR #11. Physical-device
persistence QA, backups, iOS build verification and accessibility remain
outstanding.

ObjectBox schema and generated model committed; domain models and repository boundary; plan/exercise editor, custom exercise catalog, live sets/reps/weight/RPE, rest timer, progress and session checkpoints; atomic durable write; model-migration and process-death tests. At Phase 1 this logger supported guests; Phase 2 replaces the public entry flow with mandatory initial sign-in, while preserving authenticated offline logging.

## Phase 2 — Mandatory accounts, automatic workout sync and server processing

[ADR-0005](adr/0005-mandatory-auth-and-workout-sync.md) removes guest login and keeps completed-only backup. Users must register/sign in before using NorthStar. After initial verification, workouts remain editable offline using the securely bound account. Automatically queue each NorthStar phone workout once the user finishes it; unfinished sessions stay local. Server validates and processes completed metrics. Implement owner-scoped RLS, strict DTO validation, request hashing, transactional outbox, server revision CAS, per-account cursors, restore/tombstones and conflict handling. There is no guest data to migrate; never reassign local workouts between accounts. Custom plans, exercise definitions outside history, local recovery checkpoints, preferences and health-platform observations stay local. P2-01 (backend), P2-02 (required account) and P2-03 (durable outbox) are merged. P2-04 automatic foreground uploader **merged in PR #16**, with account-matched JWTs, durable retry and CAS. P2-05 server progress aggregation is **in progress in draft PR #17**. P2-06 restoration/conflict resolution, P2-07 account/sync UI and P2-08 end-to-end release QA remain pending. P2-04 remains foreground best-effort; real-account E2E and physical-device testing are release gates.


### Phase 2 milestone tracker (26 October 2026)

| Milestone | GitHub PR | Implementation status | Outstanding gate |
| --- | --- | --- | --- |
| P2-01 — Supabase schema, authentication boundaries and sync RPC | #13 | **Merged** | Real-account isolation/device E2E |
| P2-02 — Mandatory Flutter auth and bound account storage | #14 | **Merged** | Physical-device secure-storage QA |
| P2-03 — Durable completed-workout outbox | #15 | **Merged** | Device rollback/restart QA |
| P2-04 — Automatic authenticated foreground uploader | #16 | **Merged** | Live JWT/RLS and network interruption tests |
| P2-05 — Server-side workout progress | [#17](https://github.com/mishraaditya595/northstar-health/pull/17) | **Review candidate (check live PR state)** | Expanded SQL tests, independent security review, live Auth/RLS, controlled deployment |
| P2-06 — Multi-device restore and conflicts | — | Planned | Owner cursor/tombstones, dependency-aware queue |
| P2-07 — Account, progress/sync status, export and deletion UI | — | Planned | Explicit sync failure recovery and data rights |
| P2-08 — End-to-end validation and release readiness | — | Planned | iOS/Android physical-device, performance, CI/CD gates |

This is the repository's authoritative **implementation milestone tracker**; "merged" does **not** mean released or deployed. Phase 2 is complete only after the remaining release and data-rights gates pass.

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
