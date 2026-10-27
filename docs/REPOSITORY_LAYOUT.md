# Production monorepo layout — implementation guide

**Decision:** [ADR-0004](adr/0004-production-monorepo.md). Mobile Flutter, native Apple Watch and native Wear OS have separate build boundaries and a shared **language-neutral event contract**, not shared database files.

| Path | Owner | What builds |
| --- | --- | --- |
| `apps/mobile/` | Flutter team/agents | Android/iOS app, adaptive phones/iPads/tablets |
| `apps/watch_os/` | Swift/watch team | SwiftUI sources + XcodeGen watch **proof target**; future real embedded iPhone companion target |
| `apps/wear_os/` | Kotlin/watch team | Gradle/Compose watch app artifact |
| `contracts/workout_sync/v1/` | Shared protocol reviewers | JSON Schema + fictional positive/negative fixtures |
| `supabase/` | Cloud/data reviewers | Versioned sync/progress/restore/deletion migrations, RLS, workout-only backup and server-only Auth deletion function |
| `packages/` | Dart domain team | Only actual reusable Dart packages; currently none |
| `experiments/` | Research agents | FlutterWear/FlutterWatch proof-of-concepts, excluded from release |
| `prototypes/` | Design team | HTML reference, unchanged |
| `docs/` | All | Architecture, privacy, agent review and release gates |

## Bootstrapping and verification

The bootstrap PR moved Flutter sources and configuration into `apps/mobile/` and committed native Android/iOS runners and `pubspec.lock`. Normal CI **must not regenerate project files**. If re-creating a platform runner is unavoidable, do so deliberately with a pinned Flutter SDK from `apps/mobile`, inspect the generated diff and preserve approved bundle identifiers/signing. Release builds still require native/device QA.

Wear OS uses native Gradle/JDK 17 and a committed official Gradle Wrapper. watchOS uses XcodeGen for a **temporary watch-only proof target**, but this does **not satisfy** Apple Watch companion packaging: Xcode must associate target and embedding with Flutter Runner's iOS application, with agreed bundle IDs and signing. This must be configured and tested on macOS, with no Swift source duplication; see [watchOS README](../apps/watch_os/README.md).

## Constraints and release gates

- No phone watch service, HealthKit/Health Connect permissions, database encryption or Firebase automatic collection added as part of moving folders.
- Watch local recording/outbox and two-stage ACK must be implemented in later work; placeholder UI must say so.
- Do not introduce a fake `android/`, `ios/` or watchOS Xcode `pbxproj` by writing guessed native files by hand; use and review generated tool output.
- Mobile Android debug build, Flutter formatting/analyzer/tests, Wear Gradle debug compile, protocol fixtures, macOS iOS/watchOS builds, physical watches, signing/archiving, background workout and privacy tests are distinct gates.
- If the watchOS standalone proof target is replaced by final companion target, keep the single source in `apps/watch_os/Sources`.
