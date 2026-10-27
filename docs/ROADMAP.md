# NorthStar implementation roadmap

**Initial foundation (merged PR #2):** Flutter demo screens, Performance V2 reference, adaptive light/dark design, Riverpod, routing, agent rules, ObjectBox package configuration, ADRs and CI. This is not a production health application.

## Production structure/bootstrap — merged scaffold

Flutter lives in `apps/mobile/` with version-controlled Android and iOS runners. Standalone non-recording native `apps/watch_os` and `apps/wear_os` scaffolds and the `contracts/workout_sync/v1` schema/fixtures are present. **Apple Watch target embedding, signing, companion distribution and physical-device verification are still release gates.**

## Phase 1 — Reliable offline workout logger

Implementation reports and PR scopes live under
[docs/implementation/](implementation/README.md). The foundation and
exercise/plan catalog and local session lifecycle engine (no UI) are implemented;
the active logging UI and rest timer have been merged in PR #10;
completed workout history/progress was merged in PR #11. Physical-device
persistence QA, backups, iOS build verification and accessibility remain
outstanding.

ObjectBox schema and generated model committed; domain models and repository boundary; plan/exercise editor, custom exercise catalog, live sets/reps/weight/RPE, rest timer, progress and session checkpoints; atomic durable write; model-migration and process-death tests. At Phase 1 this logger supported guests; Phase 2 replaces the public entry flow with mandatory initial sign-in, while preserving authenticated offline logging.

## Phase 2 — Mandatory accounts, automatic workout sync and server processing

[ADR-0005](adr/0005-mandatory-auth-and-workout-sync.md) removes guest login and keeps completed-only backup. Users must register/sign in before using NorthStar. After initial verification, workouts remain editable offline using the securely bound account. Automatically queue each NorthStar phone workout once the user finishes it; unfinished sessions stay local. Server validates and processes completed metrics. Implement owner-scoped RLS, strict DTO validation, request hashing, transactional outbox, server revision CAS, per-account cursors, restore/tombstones and conflict handling. There is no guest data to migrate; never reassign local workouts between accounts. Custom plans, exercise definitions outside history, local recovery checkpoints, preferences and health-platform observations stay local. P2-01 (backend), P2-02 (required account) and P2-03 (durable outbox) are merged. P2-04 automatic foreground uploader **merged in PR #16**, with account-matched JWTs, durable retry and CAS. P2-05 server progress aggregation **merged in PR #17** (not yet deployed to the hosted database). P2-06 restore, foreground orchestration, queue fairness, completed-workout deletion and reviewed conflict recovery were merged in PRs #18–#24. P2-07a account/sync UI (#25), P2-07b owner-scoped JSON cloud-history export (#27) and P2-07c freshly reverified, server-only permanent account deletion (#29) are **merged in source**, including ADR-0007's two user-confirmed uncertain-recovery exits. **None of these merges proves hosted deployment or native-device/security acceptance.** P2-08 end-to-end release QA remains pending; the export's provisional 4 MiB ceiling must be addressed before release. P2-04 remains foreground best-effort; real-account E2E and physical-device testing are release gates.


### Phase 2 milestone tracker (27 October 2026)

| Milestone | GitHub PR | Implementation status | Outstanding gate |
| --- | --- | --- | --- |
| P2-01 — Supabase schema, authentication boundaries and sync RPC | #13 | **Merged** | Real-account isolation/device E2E |
| P2-02 — Mandatory Flutter auth and bound account storage | #14 | **Merged** | Physical-device secure-storage QA |
| P2-03 — Durable completed-workout outbox | #15 | **Merged** | Device rollback/restart QA |
| P2-04 — Automatic authenticated foreground uploader | #16 | **Merged** | Live JWT/RLS and network interruption tests |
| P2-05 — Server-side workout progress | [#17](https://github.com/mishraaditya595/northstar-health/pull/17) | **Merged 2026-10-26** | Hosted migration drift, independent security review, live Auth/RLS, controlled deployment |
| P2-06 — Multi-device restore and conflicts | [#24](https://github.com/mishraaditya595/northstar-health/pull/24) and prior #18–#23 | **Merged 2026-10-27** (not deployed/released) | Hosted signed-JWT, two-device and physical-device E2E are P2-08 gates |
| P2-07 — Account, progress/sync status, export and deletion UI | [#25](https://github.com/mishraaditya595/northstar-health/pull/25), [#27](https://github.com/mishraaditya595/northstar-health/pull/27), [#29](https://github.com/mishraaditya595/northstar-health/pull/29) | **All merged in source (2026-10-27); not deployed/released** | Native picker/large-history export QA, fresh-session deletion and both uncertain-recovery exits on devices, hosted Auth/JWT/RLS and cascade verification |
| P2-08 — End-to-end validation and release readiness | [Export matrix](implementation/phase-2/p2-08-workout-export-release-validation.md), [deletion runbook](../supabase/ACCOUNT_DELETION_RUNBOOK.md) | **Pending; no release sign-off recorded** | Hosted migration reconciliation (11 committed files), signed-JWT/RLS and two-device E2E, deleted-user stale-JWT tests, physical-device lifecycle and memory QA, all-history export, security/privacy, performance and CI/CD gates |

This is the authoritative **implementation milestone tracker**. P2-01–P2-07 implementation is merged, while **Phase 2 release acceptance remains open**. Merged, deployed, tested on hardware and released are distinct states; consult [RELEASE.md](RELEASE.md) before shipping.

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
