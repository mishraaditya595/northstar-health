# NorthStar Health

**Train consistently. Understand your health. Keep control of your data.**

NorthStar is a proposed privacy-conscious, offline-first health and strength-training app for **Android, iPhone, Android tablets and iPad**, with **Apple Watch and Wear OS** companions planned. Build the Flutter product with a distinct athletic performance aesthetic, not a generic wellness dashboard.

> **Development status — Phase 2 (accounts and completed-workout sync) in progress; not released.** Implemented and merged: the local ObjectBox exercise catalog, plan editor, active workout logger with rest timer, and workout history/progress (Phase 1); mandatory email-code sign-in with account-bound offline storage, a durable completed-workout outbox, an authenticated foreground uploader and server-side progress against a **development** Supabase backend (P2-01 to P2-05). P2-06 multi-device restore, workout deletion and reviewed conflict recovery are merged (not necessarily hosted). P2-07 account/sync status UI (#25) provides local status, manual sync and reviewed recovery; P2-07b authenticated cloud JSON export (#27) is implemented in code; P2-07c permanent account deletion is under review in draft PR #29, not deployed or release-validated. Native file-picker and hosted security tests remain release gates. There is **no HealthKit/Health Connect integration, Firebase collection or shipping wearable app**, and nothing is deployed to production. See the [roadmap tracker](docs/ROADMAP.md) for exact status. The pictures below are **proposed static UI concepts**, not application screenshots.

## UI concept previews

### Phone — Today, Train and Health

![NorthStar mobile UI concept previews — dark-mode Today and Health screens plus light-mode Train. Fictional demonstration data.](docs/assets/prototype-mobile.svg)

### Tablet and smartwatch — Progress, set logging and rest timer

![NorthStar adaptive tablet and smartwatch concept screens — light tablet Progress view and dark watch workout controls. All values are fictional.](docs/assets/prototype-tablet-watch.svg)

<small>Visual references follow the existing [Performance V2 design language](docs/DESIGN_SYSTEM.md). Tablet and watch compositions are proposed extensions—not evidence of implemented features, sensor readings or tested watch runtime.</small>

## Product foundations

| Area | Decision | Delivery |
| --- | --- | --- |
| Mobile platform | Flutter, iOS / iPadOS / Android and tablet layouts | Fixture app scaffolded |
| State + dependency injection | Riverpod 3 | Theme state scaffolded |
| Navigation | go_router, bottom tabs / adaptive side rail | Scaffolded |
| On-device workout data | **ObjectBox** | Local model, repositories, exercise catalog, plan editor, live logging and history implemented |
| User identity + completed-workout sync | **Supabase Auth + PostgreSQL** | Mandatory sign-in, outbox, foreground upload and completed-workout restore/recovery (#18–#24); P2-07 account/sync UI (#25) |
| Health measurements | **Apple HealthKit and Android Health Connect** | Permissioned read planned; no SDK permissions yet |
| Workout summary write-back | One app-owned completed workout, opt-in, no duplicates | Planned |
| Crash/usage telemetry | **Firebase Crashlytics + Analytics** | Chosen, **not installed/collecting**; explicit privacy gate |
| Watches | Native HealthKit workout service / Wear OS Health Services, watch UI under evaluation | Architecture/PoC only |

The data policy is narrow: NorthStar **owns detailed workout logs**; HealthKit and Health Connect remain the source for physiology; Supabase receives only authenticated **completed NorthStar-authored phone workouts** and essential exercise/set history, per [ADR-0005](docs/adr/0005-mandatory-auth-and-workout-sync.md). No heart-rate/HRV/sleep/SpO₂/steps sensor stream, health-platform cache, imported external workout, or location trail is backed up to Supabase. Plans/templates remain **local-only initially**: a reinstall will restore past finished sessions but not necessarily user-created plans.

## Production monorepo structure

```text
apps/
  mobile/                      # Flutter app (Android, iPhone, iPad, tablets)
    android/                   # committed native runner, generated with Flutter SDK
    ios/                       # committed iOS Runner Xcode project
    lib/                       # feature-first Dart app, Riverpod/go_router
    test/                      # Dart unit/widget tests
    pubspec.yaml               # only production Dart pub package for now
    pubspec.lock               # resolved mobile dependencies
  watch_os/                    # separate single-source SwiftUI watchOS app
    Sources/App/               # native watch entry
    Sources/Features/Workout/  # non-recording preview
    project.yml                # XcodeGen compile target; companion embedding pending
  wear_os/                     # separate native Wear OS app (Kotlin/Compose)
    app/src/main/              # watch-specific manifest/activity
    gradlew                    # Gradle wrapper
contracts/workout_sync/v1/    # language-neutral event schema + tested fixture JSON
packages/                     # Dart workspace packages when there is real reuse
supabase/                     # versioned development RPC/database migrations and pgTAP tests
experiments/                  # isolated Flutter-on-watch spikes; not in release
prototypes/performance-v2/     # preserved original HTML/CSS/JS clickable reference
docs/                         # ADRs, security, design, cloud sync, watch and release
.github/workflows/            # mobile, Wear and protocol quality gates
AGENTS.md                     # repository-wide AI coding and review instructions
```

**Not a released health product:** local workout logging, sign-in and completed-workout upload exist in code, but nothing has been released, the Supabase backend is development-only and not production-ready, and native Apple Health/Health Connect integrations, Firebase and live watch recording are not implemented. Watch source now has native non-recording starter UI; the Xcode watch target must still be embedded in the iOS Runner and validated for companion signing/distribution before release.

Read [monorepo boundaries](docs/REPOSITORY_LAYOUT.md), [ADR-0004](docs/adr/0004-production-monorepo.md), [watchOS setup](apps/watch_os/README.md), [Wear OS setup](apps/wear_os/README.md), and the [watch sync contract](contracts/workout_sync/v1/README.md). Also see [AGENTS.md](AGENTS.md), [ADR-0003](docs/adr/0003-data-cloud-health.md) and the [independent review checklist](docs/REVIEW_GUIDE.md).

## Codemagic CI/CD (planned)

The repository-root [`codemagic.yaml`](codemagic.yaml) contains **11 manual-only templates** for Flutter Android/iOS, native Wear OS/watchOS and quality checks, including debug, profile, simulator, Ad Hoc and release variants. **They are placeholders, not functioning build or publishing pipelines**; each intentionally fails if manually launched before configuration. Read [Codemagic setup and rollout](docs/CODEMAGIC.md) before activating any builds. Existing GitHub Actions checks remain active until equivalent Codemagic jobs are tested.

## Flutter local setup

CI uses Flutter **3.47.7 stable** and runs from **`apps/mobile`**, not repository root. Native platform runners and `pubspec.lock` belong under `apps/mobile/` and must be committed after generation, audited for package IDs/platform deployment requirements and compiled on devices.

```sh
cd apps/mobile
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

**Running the app needs a Supabase backend** because sign-in is mandatory. Create your own free project and follow [Run NorthStar against your own Supabase project](docs/CONTRIBUTOR_SUPABASE_SETUP.md), then run `flutter run --dart-define-from-file=supabase.local.json`.

To build the Wear OS app, follow [apps/wear_os/README.md](apps/wear_os/README.md). To generate and inspect the watchOS target on macOS, follow [apps/watch_os/README.md](apps/watch_os/README.md). Both target official native SDKs; experiment with Flutter watch rendering under `experiments/` separately. Never assume a watch app is distributed simply because source code exists in the monorepo.

ObjectBox code generation must continue in **`apps/mobile`** when first entities exist: `dart run build_runner build --delete-conflicting-outputs`; commit `apps/mobile/lib/objectbox.g.dart` with `apps/mobile/lib/objectbox-model.json`.

## Explore the current HTML prototype

```sh
cd prototypes/performance-v2
python3 -m http.server 4173
```

Visit http://localhost:4173 for the original interactive mobile-only concept (Today, Train, Progress, Health, workout simulation, onboarding and appearance switching). Its fake data/actions are **not** integrations.

## Trust, safety and future delivery

Workouts must save locally before confirming success. Supabase updates require account ownership, server-enforced revision checks, idempotent operations and deletion semantics. Watch log delivery requires **two distinct acknowledgments**: durable phone receipt and separately confirmed cloud backup. Apple Watch `HKWorkout` written on-watch must not be duplicated by the phone. Firebase must remain off until consent and sanitization controls are reviewed. Phone/tablet access, low-end-device performance and physical-watch background reliability are release gates.

## Contributing

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md): it explains what's in scope, how to run the app against [your own Supabase project](docs/CONTRIBUTOR_SUPABASE_SETUP.md), the checks your PR must pass, and the rules for AI-assisted contributions.

## License

NorthStar is licensed under the [Mozilla Public License 2.0](LICENSE). You may use, modify and distribute it, including in larger proprietary works, but modified versions of NorthStar's own files must remain available under MPL-2.0. Contributions are accepted under the same license.

See [Phase 1 implementation notes](docs/implementation/README.md) for the
repository's current offline feature scope, tests and deferred QA.
