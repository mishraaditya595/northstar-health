# watchOS agent instructions

Inherits ../../AGENTS.md and docs/WEARABLES.md. This folder contains the SwiftUI watch application sources and XcodeGen target definition.

- Native HealthKit (`HKWorkoutSession` / `HKLiveWorkoutBuilder`) owns live sensor/workout sessions when implemented, never an ephemeral SwiftUI view.
- A durable on-watch workout journal and sync outbox must exist **before** enabling real workout logging; app-to-phone WatchConnectivity transport is not an acknowledgment of disk persistence.
- Share language-neutral `contracts/workout_sync/v2` and `contracts/watch_link/v1` fixtures with mobile/Wear OS. Do not copy ObjectBox runtime or a Dart package into watchOS.
- Never include unreviewed HealthKit permissions, background modes, workout export, health value telemetry or signing credentials.
- The watch app is embedded in the iPhone Runner project by `tool/embed_watch_target.rb` (an unsigned simulator build runs in CI; the signed TestFlight archive, pairing and every device check are unverified). Run the script after adding or removing a watch Swift file or the asset catalog, and keep the sources only here. Do not describe the watch as shipped; run Xcode and physical watch tests on macOS before release.
