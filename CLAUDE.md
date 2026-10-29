# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

`AGENTS.md` (imported above) holds the binding rules: data ownership, durable write/sync contract, review checklist, Codemagic limits. Nested `AGENTS.md` files in `apps/mobile/`, `apps/watch_os/`, `apps/wear_os/` add per-app rules — read the one for the app you touch.

## Project state

Phase 2 in progress, nothing released. `docs/ROADMAP.md` (Phase 2 milestone tracker) is the source of truth; check it before describing status.

- **Implemented:** ObjectBox workout/plan/exercise storage, plan editor, active workout logger, rest timer and history/progress (Phase 1); mandatory email-code sign-in, account-partitioned ObjectBox, durable completed-workout outbox, authenticated foreground uploader, server-side progress RPC (P2-01–P2-05), multi-device restore and reviewed conflict recovery (#18–#24).
- **P2-07:** Account/sync status UI (#25), cloud workout JSON exporter (#27, implementation in code), and permanent account deletion (draft PR #29, not deployed or security-validated). Export larger than 4 MiB provisional, unmeasured on low-memory hardware and physical-device delivery remain release gates, as do P2-08 hosted security and device checks.
- **Not implemented:** HealthKit/Health Connect, Firebase, watch workout recording, iPhone companion embedding, permanent account deletion in production, production deployment. Never describe these as implemented, and never report Codemagic templates as working builds (they intentionally fail).
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

# watchOS proof target (macOS)
cd apps/watch_os && xcodegen generate --spec project.yml
xcodebuild -project NorthStarWatch.xcodeproj -scheme NorthStarWatch -configuration Debug \
  -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

`tool/test_*.py` enforce README asset paths, monorepo layout, Codemagic config shape and protocol fixtures — moving files or editing `codemagic.yaml`/README images can break them.

## Architecture

- `apps/mobile/lib/`: `app/` (app shell, router, theme controller), `core/design/` (shared component kit and Performance V2 tokens), `core/storage/` (account-bound ObjectBox), `features/` feature-first modules (`account`, `sync`, `workouts`, `train`, `progress`, `today`, `health`). UI renders Riverpod state; platform/storage/network access goes through repositories, never widgets.
- `apps/watch_os/` (SwiftUI + XcodeGen) and `apps/wear_os/` (Kotlin/Compose, Gradle) are independent native apps, not Flutter. Watch Swift sources live only in `apps/watch_os/Sources`, not in `apps/mobile/ios`.
- `contracts/workout_sync/v1/`: language-neutral JSON Schema envelope + fixtures; the only shared wire contract between phone and watches (no shared Dart models).
- `prototypes/performance-v2/`: original HTML prototype, visual authority alongside `docs/DESIGN_SYSTEM.md`. Do not modify. Run: `cd prototypes/performance-v2 && python3 -m http.server 4173`.
- `supabase/`: migrations (sync RPC, RLS, progress, restore feed) and pgTAP tests; CI replays all migrations. `packages/`, `experiments/`: placeholders/isolation boundaries.
- Decisions live in `docs/adr/`; policy/provider/backup-scope/watch-ownership changes need a new numbered ADR.
