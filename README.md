# NorthStar Health

**Train consistently. Understand your health. Keep control of your data.**

NorthStar is a proposed privacy-conscious, offline-first health and strength-training app for **Android, iPhone, Android tablets and iPad**, with **Apple Watch and Wear OS** companions planned. Build the Flutter product with a distinct athletic performance aesthetic, not a generic wellness dashboard.

> **Development status — foundation only.** The Flutter code currently provides fictional demo screens, Riverpod-based theme settings, routing, responsive navigation, quality checks and technical design documents. There is **no functioning workout database, cloud backup, wearable app, Firebase collection, or HealthKit/Health Connect connection**. The pictures below are **proposed static UI concepts**, not functioning application screenshots.

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
| On-device workout data | **ObjectBox** | Packages added; actual entity model pending |
| User identity + workout-only backup | **Supabase Auth + PostgreSQL** | Architectural decision; not integrated |
| Health measurements | **Apple HealthKit and Android Health Connect** | Permissioned read planned; no SDK permissions yet |
| Workout summary write-back | One app-owned completed workout, opt-in, no duplicates | Planned |
| Crash/usage telemetry | **Firebase Crashlytics + Analytics** | Chosen, **not installed/collecting**; explicit privacy gate |
| Watches | Native HealthKit workout service / Wear OS Health Services, watch UI under evaluation | Architecture/PoC only |

The data policy is narrow: NorthStar **owns detailed workout logs**; HealthKit and Health Connect remain the source for physiology; Supabase receives only authenticated **completed NorthStar workout history** and essential exercise snapshots. No heart-rate/HRV/sleep/SpO₂/steps sensor stream, health-platform cache, imported external workout, or location trail is backed up to Supabase. Plans/templates remain **local-only initially**: a reinstall will restore past finished sessions but not necessarily user-created plans.

## Development repository

```text
lib/
  app/                      # routing and adaptive app shell
  core/design/              # theme and UI components
  features/                 # Today, Train, Progress, Health demo views
test/                       # Flutter widget tests
docs/
  adr/                      # binding architectural decisions
  assets/                   # proposed static UI concept art for README
  OBJECTBOX.md              # local object-store contract
  CLOUD_SYNC.md             # auth / backup / compare-and-set / conflict contract
  HEALTH_DATA.md            # platform reads, permissions and deduplicated export
  SYNC_PROTOCOL.md          # watch -> phone -> cloud durable acknowledgments
  WEARABLES.md              # native watch workout engines and UI PoC criteria
  FIREBASE_PRIVACY.md       # default-off telemetry controls and allowlists
  DESIGN_SYSTEM.md          # visual language from reference prototype
prototypes/performance-v2/  # preserved original HTML/CSS/JS interactive prototype
.github/                    # quality checks and PR review template
AGENTS.md                   # binding AI coding / design / review instructions
```

Read [AGENTS.md](AGENTS.md) before starting agent-led development. For decisions see [ADR-0001](docs/adr/0001-foundation.md) (mobile foundation), [ADR-0002](docs/adr/0002-watch-workout-architecture.md) (watches), and **[ADR-0003](docs/adr/0003-data-cloud-health.md)** (local/cloud/health/Firebase ownership). Additional guidance: [Architecture](docs/ARCHITECTURE.md), [Roadmap](docs/ROADMAP.md), [Independent code review](docs/REVIEW_GUIDE.md).

## Flutter setup

CI uses Flutter **3.47.7 stable** and validates dependency resolution, formatter, static analysis and widget tests. Native `android/`, `ios/` runners and the `pubspec.lock` still need to be generated and committed in a reviewed platform bootstrap PR; CI currently generates transient runners. On a machine with Flutter and required Android SDK / Xcode setup:

```sh
flutter create --platforms=android,ios --project-name=northstar_health --org=dev.northstar .
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run
```

After introducing ObjectBox annotated entities, use `dart run build_runner build --delete-conflicting-outputs` and commit **both** `lib/objectbox.g.dart` and `lib/objectbox-model.json`. Do not reset model UIDs.

## Explore the current HTML prototype

```sh
cd prototypes/performance-v2
python3 -m http.server 4173
```

Visit http://localhost:4173 for the original interactive mobile-only concept (Today, Train, Progress, Health, workout simulation, onboarding and appearance switching). Its fake data/actions are **not** integrations.

## Trust, safety and future delivery

Workouts must save locally before confirming success. Supabase updates require account ownership, server-enforced revision checks, idempotent operations and deletion semantics. Watch log delivery requires **two distinct acknowledgments**: durable phone receipt and separately confirmed cloud backup. Apple Watch `HKWorkout` written on-watch must not be duplicated by the phone. Firebase must remain off until consent and sanitization controls are reviewed. Phone/tablet access, low-end-device performance and physical-watch background reliability are release gates.

## License

No repository license has been selected. A publicly visible repository is not automatically open-source-licensed.
