# NorthStar architecture and technology decisions

## Stack (decided vs implemented)

| Concern | Decision | Current implementation status |
| --- | --- | --- |
| Mobile/iPad/tablet UI | Flutter Material 3, Performance V2 semantic tokens | Offline logger, exercise catalog, plans, history/progress, account UI implemented; physical-device/adaptive QA pending |
| State and DI | Riverpod 3 providers/notifiers | App, workouts, auth and sync controllers in source |
| Navigation | go_router | Feature/account navigation in source |
| Durable mobile storage | **ObjectBox** | Transactional repositories, owner-bound partitions, outbox and restore state implemented |
| Appearance preferences | shared_preferences (non-sensitive) | Theme preference implemented |
| Identity and cloud sync | **Supabase Auth + PostgreSQL** | Mandatory email OTP, completed-only foreground upload/restore, tombstones, conflict review, JSON export and permanent deletion merged through P2-07c; hosted QA pending |
| Health inputs | **HealthKit (Apple), Health Connect (Android)** | Planned permission-based reads; no live integration |
| Workout health export | Optional, permission-controlled **summary only** | Planned; distinct from implemented Supabase JSON history export |
| Watch sensors | watchOS HealthKit workout sessions; Wear OS Health Services | Non-recording native starter targets, no shipping sessions |
| Watch transport | Versioned durable events and replay-safe ACKs | Contract/fixtures only; watch-to-phone delivery not active |
| Diagnostics | **Firebase Crashlytics + Analytics** | Off/unconfigured; no collection |
| CI | GitHub checks; Codemagic planned | GitHub Actions present; Codemagic templates intentionally inactive |

## Authoritative decisions

- [ADR-0001](adr/0001-foundation.md): Flutter, Riverpod, go_router, adaptive layout, local-first. *Backend/diagnostics rows superseded by ADR-0003.*
- [ADR-0002](adr/0002-watch-workout-architecture.md): sensor-native watch workout architecture with trial of Flutter watch UIs.
- **[ADR-0003](adr/0003-data-cloud-health.md): ObjectBox ownership, health read/export and Firebase policy; cloud-scope/auth clauses superseded by [ADR-0005](adr/0005-mandatory-auth-and-workout-sync.md).**
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
        +--- WorkoutCloudSync --------> Supabase (completed NorthStar workouts)
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
- **Cloud sync requires an account**, and backs up completed NorthStar-authored phone workouts only. Unfinished sessions, rest timer/checkpoint data and custom plans/catalogs remain local. No health measurements in cloud. See ADR-0005.
- Platform health store remains the source of measurements. ObjectBox health caches are expiring and never remotely uploaded.
- Watch-generated set logs are backed up through phone coordinator. On-watch durable storage is independent of mobile ObjectBox.
- Origin/writer and platform export receipt prevent duplicate HealthKit/Health Connect workouts.
- SDK telemetry is **not active** before separate consent, privacy and sanitization implementation.

## Adaptive/performance requirements

Use `LayoutBuilder` and available content width (compact under ~600dp -> bottom nav; expanded -> rail with constrained max-width). Do not device-sniff or lock portrait. Account for tablets in split view, keyboard/rotary focus, text scale, safe areas and reduced motion. No parsing/DB bulk queries or expensive imports from widget build; paginate health reads and test physical low-memory Android. A workout timer tick should update only the necessary view, not rebuild the entire dashboard.

## Implementation truth

Phase 1 local workout flows and P2-01–P2-07 source implementations are merged. The app uses mandatory Auth and per-account ObjectBox partitions, durable completed-only outbox, serialized **foreground** upload/pull, reviewed conflict resolution, account/sync controls, owner-scoped cloud-history JSON export and freshly verified server-side account deletion. The P2-07c deletion endpoint and its fresh-session SQL gate are committed but **not asserted to be deployed or tested with real accounts**. Uncertain deletion results keep the original partition locked; ADR-0007 separately permits the user to leave while retaining old owner-locked files or explicitly erase only that owner's local files. A confirmed server deletion may clean up that same owner's local partition. Hostile JWT/RLS, second-device, low-memory export and native-device testing remain P2-08 release gates. See [ROADMAP.md](ROADMAP.md), [CLOUD_SYNC.md](CLOUD_SYNC.md), and [RELEASE.md](RELEASE.md). No HealthKit/Health Connect, Firebase collection or live watch-session feature has shipped.

## Repository layout (ADR-0004)

Primary Flutter app path: `apps/mobile/` (`lib/`, `test/`, committed `android/` / `ios/` native runners and lockfile). Wear OS independent Android app: `apps/wear_os/`. Apple watch Swift source: `apps/watch_os/Sources/` with an XcodeGen watchOS project; the final watch companion embedding into `apps/mobile/ios` is a **pending target-integration task**, not a completed release artifact.

Cross-language event schema: `contracts/workout_sync/v1/`. Mobile backend package/code ownership is unchanged. Read [REPOSITORY_LAYOUT.md](REPOSITORY_LAYOUT.md) and [ADR-0004](adr/0004-production-monorepo.md).
