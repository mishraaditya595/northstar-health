# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

`AGENTS.md` (imported above) holds the binding rules: data ownership, durable write/sync contract, secrets in a public repository, review checklist, Codemagic limits. **This repo is public: never commit keys, signing files, `.env`/`supabase.local.json`, hosted project refs or real personal data** (see AGENTS.md "Secrets in a public repository"). Nested `AGENTS.md` files in `apps/mobile/`, `apps/watch_os/`, `apps/wear_os/` add per-app rules — read the one for the app you touch.

## Project state

Phase 2 in progress, nothing released. `docs/ROADMAP.md` (Phase 2 milestone tracker) is the source of truth; check it before describing status.

- **Implemented:** ObjectBox workout/plan/exercise storage, plan editor, active workout logger, rest timer and history/progress (Phase 1); mandatory email-code sign-in, account-partitioned ObjectBox, durable completed-workout outbox, authenticated foreground uploader, server-side progress RPC (P2-01–P2-05), multi-device restore and reviewed conflict recovery (#18–#24).
- **P2-07 (merged in source, not deployed):** Account/sync status UI (#25), cloud workout JSON export (#27), freshly reverified permanent account deletion (#29).
- **P2-08 (in progress, no release sign-off):** hosted signed-JWT/RLS harness and preflight (#31, `tool/test_p2_08_hosted_rls.py`), manual Codemagic `supabase-database`/`supabase-functions` jobs (#32, #39–#41), Semgrep and pinned Actions (#34–#37). Open gates: hosted migration reconciliation, live signed-JWT/RLS and two-device E2E, deleted-user stale-JWT tests, physical-device lifecycle/memory QA, the provisional 4 MiB export ceiling, security/privacy review. See `docs/implementation/phase-2/p2-08-workout-export-release-validation.md`.
- **Phase 3 (implemented in source, ADR-0008, not released or device-verified):** read-only daily summary (sleep, steps, resting heart rate, weight) from HealthKit/Health Connect via `health` 14.0.0, per-account opt-in, no health-value cache. See `docs/implementation/phase-3/p3-01-daily-health-summary.md`; device matrix and store gates are open in `docs/RELEASE.md`.
- **Health insights (in progress, not released, ADR-0009):** richer Health tab, 7/30-day trends and an on-device sleep score, read fresh with nothing stored. Stages 1 (richer Health tab, 7/30-day trends, sleep score, four detail screens, chart kit in `lib/core/design/charts/`) and 2 (on-device readiness score, hero card, Train note) are merged on `main` (#61, #64); stage 3 (training tie-ins: muscle recovery weighted by reps and effort, Train "Better fit today" and per-plan recovery lines, two insights joined in memory from the last 30 days, at least 5 days on each side and 30 min or 3 bpm apart, the Health tab showing one of them, sleep first) is implemented in source, not released or device-verified. A health polish stage 1 (explain sheets, Health terms page, Today readiness hero and tiles, Train start card readiness strip and today's program workout) is implemented in source, not released or device-verified. A health polish stage 2 (ADR-0011: workouts other apps saved to HealthKit / Health Connect, read fresh for 90 days and never stored, merged with overlapping BeyondRep sessions, shown in Activity, Progress history and the Today Workouts tile, plus recent training load as a fifth readiness input; Android requests only `READ_EXERCISE`) is implemented in source, not released or device-verified. The spec's other two insights (weekly volume vs readiness, weight vs strength trend) and insights on Progress are not implemented. See `docs/ROADMAP.md`; the stage-1, stage-2 and stage-3 device matrices are open in `docs/RELEASE.md`.
- **Phase 4 stage 1, tablet layouts (implemented in source, not released or device-verified):** on windows 840 dp and wider Today, Health (card grid and split detail screens), Progress history, the Exercises, Workouts and Programs lists (list and detail pane) and Train use two columns; layout primitives in `lib/core/design/layout.dart`. Watch stages are not started. See `docs/ROADMAP.md` and the iPad checks in `docs/RELEASE.md`.
- **Phase 4 stage 2, message contracts and watch core (implemented in source, no UI, not device-verified, ADR-0012):** `contracts/workout_sync/v2` and `contracts/watch_link/v1` (fixtures and replay cases), Dart codecs in `lib/features/watch/domain/`, and the `apps/watch_os/Packages/BeyondRepWatchCore` Swift package (codecs, replay, session machine, SQLite journal) tested by `swift test` in `watchos_smoke.yml`. No watch screens, transport or HealthKit workout yet.
- **Training library (in progress, not released, ADR-0010, issue #63):** shared Supabase catalogue (240 exercises, 38 workout templates and 17 programs in release 4, published to the development Supabase project (release 4 live), not released to users), phone cache, exercise/workout/program browsing with filters, programs with Today card and missed days, timed sets and specific muscles. Stages 1-8 are implemented in source, not released or device-verified; stage 9 (automated accessibility, tablet and process-death tests, measured performance, owner device script) is done in source, the device script is open in `docs/RELEASE.md`. See `docs/ROADMAP.md`, `docs/CATALOG.md` and `docs/implementation/training-library/stage-9-verification.md`.
- **Not implemented:** HealthKit/Health Connect writes or exports, Firebase, watch workout recording, iPhone companion embedding, any hosted deployment or release. Never describe these as implemented. The other 9 app/watch Codemagic templates intentionally fail; never report them as working builds. The manual `mobile-ios-testflight` job (internal TestFlight upload, see `docs/IOS_TESTFLIGHT_CODEMAGIC.md`), the manual `mobile-android-release` job (upload-key-signed AAB, draft upload to a Play testing track, see `docs/ANDROID_PLAY_CODEMAGIC.md`) and the two manual Supabase Codemagic jobs have never been run on hosted Codemagic.
- The Supabase backend is **development-only**. Running the app needs a Supabase project; see `docs/CONTRIBUTOR_SUPABASE_SETUP.md`.

## Commands

Flutter project root is `apps/mobile/` (repo root has no `pubspec.yaml`). Flutter 3.47.7 stable.

```sh
cd apps/mobile
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test                                   # all tests
flutter test test/app_test.dart                # one file
flutter test --plain-name "<test name>"        # one test
flutter run --dart-define-from-file=supabase.local.json   # needs your own Supabase project
flutter build apk --debug --no-pub
dart run build_runner build --delete-conflicting-outputs   # ObjectBox codegen; commit objectbox.g.dart + objectbox-model.json
```

Other CI gates (`.github/workflows/`):

- **Semgrep (`semgrep/ci`):** same-repo PR, `main` push, and nightly security scanning. Requires the `SEMGREP_APP_TOKEN` Actions secret; missing/invalid tokens and scanner errors fail the job. Only policies configured to **Block** fail on findings. Fork/Dependabot PRs skip; see `docs/SEMGREP.md` for setup and required smoke tests before enforcing this check.

```sh
# repo/protocol contracts (from repository root)
python3 -m pip install -r tool/requirements-ci.txt
python3 -m unittest discover -s tool -p 'test_*.py'
python3 -m unittest tool.test_protocol_contract    # single module

# Wear OS (JDK 17, Android SDK 35)
cd apps/wear_os && ./gradlew :app:assembleDebug

# website (apps/website, Node 22.23.4+; CI: .github/workflows/website_ci.yml)
cd apps/website && npm ci && npm test && npm run build && npm run check-links

# watchOS proof target (macOS)
cd apps/watch_os && xcodegen generate --spec project.yml
xcodebuild -project BeyondRepWatch.xcodeproj -scheme BeyondRepWatch -configuration Debug \
  -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

`tool/test_*.py` enforce README asset paths, monorepo layout, Codemagic config shape and protocol fixtures — moving files or editing `codemagic.yaml`/README images can break them.

## Architecture

- `apps/mobile/lib/`: `app/` (app shell, router, theme controller), `core/design/` (shared component kit and Performance V2 tokens), `core/storage/` (account-bound ObjectBox), `features/` feature-first modules (`account`, `sync`, `workouts`, `train`, `progress`, `today`, `health`). UI renders Riverpod state; platform/storage/network access goes through repositories, never widgets.
- `apps/watch_os/` (SwiftUI + XcodeGen) and `apps/wear_os/` (Kotlin/Compose, Gradle) are independent native apps, not Flutter. Watch Swift sources live only in `apps/watch_os/Sources`, not in `apps/mobile/ios`.
- `apps/website/`: static Astro site for beyondrep.in (marketing, draft privacy/account-deletion/terms pages, deployed by Cloudflare Pages). Shares no code with the apps; rules in its `AGENTS.md`.
- `contracts/workout_sync/v1/`: language-neutral JSON Schema envelope + fixtures; the only shared wire contract between phone and watches (no shared Dart models).
- `prototypes/performance-v2/`: original HTML prototype, visual authority alongside `docs/DESIGN_SYSTEM.md`. Do not modify. Run: `cd prototypes/performance-v2 && python3 -m http.server 4173`.
- `supabase/`: migrations (sync RPC, RLS, progress, restore feed) and pgTAP tests; CI replays all migrations. `packages/`, `experiments/`: placeholders/isolation boundaries.
- Decisions live in `docs/adr/`; policy/provider/backup-scope/watch-ownership changes need a new numbered ADR.
