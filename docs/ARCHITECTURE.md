# NorthStar architecture and technology decisions

## Stack (decided vs implemented)

| Concern | Decision | Current foundation status |
| --- | --- | --- |
| Mobile/iPad/tablet UI | Flutter Material 3 with Performance V2 semantic tokens | Demo screens implemented |
| State and DI | Riverpod 3 providers/notifiers | Theme implemented |
| Navigation | go_router | Four fixture sections implemented |
| Durable mobile storage | **ObjectBox** | Dependencies present; first entities/repositories not implemented |
| Appearance preferences | shared_preferences (non-sensitive) | Theme preference implemented |
| User identity and workout backup | **Supabase Auth + PostgreSQL** | Approved architecture; not implemented |
| Health inputs | **HealthKit (Apple), Health Connect (Android)** | Permission-based, read-only measurements in MVP; not implemented |
| Workout health export | Optional permission-controlled **summary only** | Approved architecture; not implemented |
| Watch sensors | watchOS HealthKit workout sessions; Wear OS Health Services | Native session ownership; apps/prototypes not built |
| Watch transport | Versioned durable events, replay-safe acknowledgment | Contract documented, not implemented |
| Diagnostics | **Firebase Crashlytics + Firebase Analytics** | Collection off/unconfigured; not implemented |
| CI | Format, analyze, Flutter widget tests | GitHub Actions enabled |

## Authoritative decisions

- [ADR-0001](adr/0001-foundation.md): Flutter, Riverpod, go_router, adaptive layout, local-first. *Backend/diagnostics rows superseded by ADR-0003.*
- [ADR-0002](adr/0002-watch-workout-architecture.md): sensor-native watch workout architecture with trial of Flutter watch UIs.
- **[ADR-0003](adr/0003-data-cloud-health.md): ObjectBox ownership, narrow Supabase backup, health read/export and Firebase policy.**
- [ObjectBox](OBJECTBOX.md), [Cloud sync](CLOUD_SYNC.md), [Health data](HEALTH_DATA.md), [Firebase privacy](FIREBASE_PRIVACY.md), [Watch architecture](WEARABLES.md), [Event protocol](SYNC_PROTOCOL.md).

## Data-flow boundaries

```text
                    Flutter UI (Riverpod)
                           |
        +------------------+--------------------+
        |                  |                    |
 WorkoutRepository   HealthRepository     DiagnosticsSink
        |                  |                    |
   ObjectBox store    HealthKit /            Firebase
   sessions/sets/     Health Connect         consent-off
   plans/outbox       authorized reads
        |
        +--- WorkoutCloudSync --------> Supabase (completed workouts only)
        |
        +--- WorkoutHealthExport ----> HealthKit / Health Connect
             (completed owned sessions; summary only)

 watchOS HealthKit / Wear OS Health Services (native background)
        | watch-local durable event journal
        +---- versioned dedup / ACK ----> phone ObjectBox
```

These pipelines have **separate triggers, IDs, receipts and permissions**. Do not recursively push platform health readings into Supabase, or re-export imported workouts.

## Structural rules

- Feature-first `lib/features/<feature>/presentation`, adding `domain`/`data` as needed; `lib/app` owns routing, `lib/core` owns shared design/security/telemetry interfaces.
- Widgets do not import ObjectBox entity APIs, Supabase DTOs, HealthKit wrappers or Firebase packages. Repositories translate immutable domain models to persistence/transport.
- Store NorthStar-origin detailed workouts, plans and recovery checkpoints locally before confirming UI actions. One ObjectBox transaction also enqueues remote sync operations when appropriate.
- **Cloud only backs up completed NorthStar-created workouts with exercise snapshots**, not plans or in-progress sessions initially. Warn users that restored history excludes plans; explicit later scope review.
- Platform health store remains the source of measurements. ObjectBox health caches are expiring and never remotely uploaded.
- Watch-generated set logs are backed up through phone coordinator. On-watch durable storage is independent of mobile ObjectBox.
- Origin/writer and platform export receipt prevent duplicate HealthKit/Health Connect workouts.
- SDK telemetry is **not active** before separate consent, privacy and sanitization implementation.

## Adaptive/performance requirements

Use `LayoutBuilder` and available content width (compact under ~600dp -> bottom nav; expanded -> rail with constrained max-width). Do not device-sniff or lock portrait. Account for tablets in split view, keyboard/rotary focus, text scale, safe areas and reduced motion. No parsing/DB bulk queries or expensive imports from widget build; paginate health reads and test physical low-memory Android. A workout timer tick should update only the necessary view, not rebuild the entire dashboard.

## Implementation truth

The initial merged foundation includes a Flutter **demo**, themed fixture screens and scaffold only. ObjectBox store schema, native runners, Supabase, HealthKit, Health Connect, Firebase and watch companions require dedicated reviewed implementation and device testing.

## Repository layout (ADR-0004)

Primary Flutter app path: `apps/mobile/` (`lib/`, `test/`, committed `android/` / `ios/` native runners and lockfile). Wear OS independent Android app: `apps/wear_os/`. Apple watch Swift source: `apps/watch_os/Sources/` with an XcodeGen watchOS project; the final watch companion embedding into `apps/mobile/ios` is a **pending target-integration task**, not a completed release artifact.

Cross-language event schema: `contracts/workout_sync/v1/`. Mobile backend package/code ownership is unchanged. Read [REPOSITORY_LAYOUT.md](REPOSITORY_LAYOUT.md) and [ADR-0004](adr/0004-production-monorepo.md).
