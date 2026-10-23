# watchOS agent instructions

Inherits ../../AGENTS.md and docs/WEARABLES.md. This folder contains the SwiftUI watch application sources and XcodeGen target definition.

- Native HealthKit (`HKWorkoutSession` / `HKLiveWorkoutBuilder`) owns live sensor/workout sessions when implemented, never an ephemeral SwiftUI view.
- A durable on-watch workout journal and sync outbox must exist **before** enabling real workout logging; app-to-phone WatchConnectivity transport is not an acknowledgment of disk persistence.
- Share language-neutral `contracts/workout_sync/v1` fixtures with mobile/Wear OS. Do not copy ObjectBox runtime or a Dart package into watchOS.
- Never include unreviewed HealthKit permissions, background modes, workout export, health value telemetry or signing credentials.
- Watch Xcode packaging with iPhone Runner is a **separate gated integration step**; do not imply this source-only target is already embedded in an iOS IPA. Run XcodeGen and physical watch/Xcode tests on macOS before release.
