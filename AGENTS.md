# NorthStar agent operating agreement

Applies to **all AI coding, design, test and review agents**. Read `README.md`, `docs/ARCHITECTURE.md`, `docs/DESIGN_SYSTEM.md`, `docs/adr/0003-data-cloud-health.md`, `docs/adr/0005-mandatory-auth-and-workout-sync.md`,  `docs/OBJECTBOX.md`, `docs/CLOUD_SYNC.md`, `docs/HEALTH_DATA.md`, `docs/SYNC_PROTOCOL.md`, `docs/WEARABLES.md`, `docs/FIREBASE_PRIVACY.md`, `docs/REVIEW_GUIDE.md` before changes.

**External contributors and their agents:** the full reading list above is for maintainer-directed work on data, sync and platform features. For the scopes allowed below, read `README.md`, this file, the nested `AGENTS.md` of the app you touch, `docs/DESIGN_SYSTEM.md` (UI work) and [CONTRIBUTING.md](CONTRIBUTING.md).

## External contributions

These rules apply to every pull request from someone other than the maintainer, including PRs written wholly or partly by an AI agent.

1. **Open scope:** UI and accessibility using the existing component kit, tests for existing behavior, documentation, `apps/wear_os/` and `apps/watch_os/` non-recording UI, and bug fixes with a failing test. Work from an open issue and link it in the PR.
2. **Maintainer-approved issue required first** (a PR without one will be closed): `supabase/`, `apps/mobile/lib/features/sync/`, `apps/mobile/lib/features/account/`, `apps/mobile/lib/core/storage/`, ObjectBox entities or `objectbox-model.json`, `contracts/`, `.github/workflows/`, `codemagic.yaml`, `docs/adr/`, platform permissions, new dependencies, and anything touching health data, authentication, sync or telemetry.
3. **Do not modify** `prototypes/performance-v2/`, `LICENSE`, `.github/CODEOWNERS` or the data ownership rules below.
4. **AI disclosure:** state in the PR whether an AI agent wrote any of it and which one. The human who opens the PR is accountable for it: they must have read the whole diff, run the checks themselves, and be able to answer review questions without relaying them to the agent.
5. **Honest evidence:** list the checks you actually ran. Contributors without physical devices, watches or a Supabase project write "not run" for those items; never tick a box you did not verify.
6. **Small and focused:** one issue per PR, no drive-by refactors, formatting churn or renames. Large or speculative PRs will be closed and can be reopened as smaller pieces.
7. Use synthetic data only. Never commit keys, `supabase.local.json`, real health exports or personal data.

## Agent workflow

1. Inspect current implementation and tests. Write a focused plan describing the actual data owner, device behavior, security/permissions, recovery tests and changed files.
2. Work in a task branch; keep PRs small, reproducible and independently reviewable. Do not self-approve, merge, override a check or claim CI ran when it did not.
3. Keep Dart feature-first: UI renders Riverpod state, go_router handles routes, repositories and mappers isolate platform APIs/ObjectBox/Supabase DTOs/Firebase. No network/storage SDK use directly in widgets.
4. **Reuse the shared Flutter component kit; never invent UI components.** Text inputs, selects, dialogs, bottom sheets, chips, list cards, tags, insight cards, page headers, snackbars and buttons come from `apps/mobile/lib/core/design/` (catalog in `docs/DESIGN_SYSTEM.md`). If something is missing, extend the kit in its own small PR, theme-first, then use it. Features must not call raw `TextField`, `DropdownButton`, `AlertDialog`, `showDialog`, `showModalBottomSheet`, `ChoiceChip`/`FilterChip` or `SnackBar`; `test/design_kit_guard_test.dart` enforces this.
5. Use `prototypes/performance-v2/` and `docs/DESIGN_SYSTEM.md` as visual authority. Support light/dark, phone and tablet split screen, text scaling, accessibility, safe areas, reduced motion and low-end Android.
6. Test loading, empty, stale, denied, failure/retry, offline, process death, duplicate and account separation. Use fictional or fully synthetic test health data, never real user exports in Git.
7. From `apps/mobile/`, run `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`; include runtime and actual device tests for native/persistence/watch integration. Record all unrun checks and risks.
8. AI agents may create branches, implement changes, open PRs, address review findings, and run tests. Merging into main is prohibited.
9. State assumptions. Ask when requirements are ambiguous instead of guessing, especially for data ownership, sync and permissions.
10. Every changed line must trace to the task. Report unrelated dead code instead of removing it. Match the surrounding code's style; no unrelated formatting or cleanup.
11. Start a bug fix with a failing test. Each plan step names the check that verifies it.
12. Write the minimum code that solves the task. No speculative features, single-use abstractions or unrequested error handling, except where the durable write and conflict contract requires it.
13. Split large work into stages that are each independently verifiable and shippable.

## Data ownership hard rules

- **ObjectBox phone:** durable NorthStar workouts, exercises, sets, plans, in-progress checkpoints, outbox, export receipts; only temporary, authorized health caches.
- **Supabase:** authenticated sync/backup of **completed** NorthStar phone workouts (finished by the user) and essential exercise/set snapshots; tombstones preserve deletions. Everyone requires an account. Authenticated users can save offline and synchronize later. In-progress, paused and discarded sessions, local rest/checkpoint state, custom plans, templates, catalog, health caches, imported workouts and platform vitals are **never** backed up in this phase. See ADR-0005.
- **HealthKit/Health Connect:** source of user-authorized physiological measurements. Only app-owned completed workout **summaries** may be exported, with separate write permission, platform record identity and dedup receipts. Never fabricate calories/readiness or show missing as zero.
- **Firebase Crashlytics/Analytics:** decided provider but disabled/unconfigured until reviewed consent/redaction. Never collect user notes, health measurements, workout values, tokens, source/device IDs or raw API errors. Sentry is no longer the selected solution.
- **Authentication/identity:** everyone must register/sign in before entering workout features (no guest mode); initial login requires internet. Returning authenticated users may save offline. Never keep tokens in ObjectBox or service_role/secret keys in Flutter or Git; account-scoped RLS and replay-safe RPC; never attach local workouts to a different account.

## Durable write and conflict contract

- Local workout edit and `SyncOutbox` entry commit atomically. Show saved only after local commit. Cloud retries keep the same operation UUID, use **server-enforced expected revision compare-and-set**, preserve conflict versions and use durable ACK before dequeue.
- Watch logs its own set and event durably, phone records set+inbox receipt atomically, phone ACKs, then independently attempts Supabase backup. ACK from phone != cloud backup.
- WatchOS: native HealthKit workout engine, watch-origin `HKWorkout` saved once and never duplicated by phone. Wear OS: native Health Services session, one chosen platform export writer. UI toolkit is under device-test evaluation.
- Permission revocation invalidates cached health reads. Platform health data can **never** flow into cloud workout backups or Firebase telemetry.
- Respect ObjectBox stable model UIDs; commit generated code and `apps/mobile/lib/objectbox-model.json`; test migrations with old databases.

## Review completion checklist

**Why / changed behavior / data ownership / privacy / offline+sync state / UI light+dark+tablet evidence / tests actually run / failure and rollback / deferred functionality**. A reviewer challenges serialization contracts, migration, RLS and replays separately. Changes to policies, provider choices, backup scope or watch ownership need a numbered ADR.

## Monorepo source ownership (ADR-0004)

- `apps/mobile/` is the **Flutter project root**; Flutter CLI, pub, formatting and tests run there. Root has no `pubspec.yaml` and **no monorepo-wide Dart workspace** until a second production Dart package exists.
- `apps/watch_os/` owns SwiftUI watch implementation sources and XcodeGen proof target. iPhone Runner integration/embedded companion archive is **not complete**; do not label the watch as a shipped target or duplicate watch Swift sources in `apps/mobile/ios`.
- `apps/wear_os/` owns independent Kotlin/Compose watch app and Gradle build. Native foreground workout service is not present yet. Neither watch UI may fake a saved session.
- `contracts/workout_sync/v1/` defines portable wire messages with fixtures for eventual Swift, Kotlin and Dart adapters; no direct Dart models shared into Swift/Kotlin.
- `supabase/` remains backend schema/tests only after reviewed implementations; `packages/` and `experiments/` remain isolation boundaries. Keep original web prototype files intact.
- Read any nested `AGENTS.md` when working inside an app, and update layout/build docs when paths change.

## Codemagic rules

- `codemagic.yaml` at repo root is the **future primary CI/CD definition**. Follow `docs/CODEMAGIC.md`. Manual template stubs are deliberately nonfunctional and must not be reported as successful builds.
- Do not add automatic triggers, signing references, credential groups, release artifacts or publishing before owner-approved integration and explicit privacy/security review.
- Keep existing GitHub Actions quality gates until matching Codemagic validation actually passes; avoid duplicate builds after cutover.
