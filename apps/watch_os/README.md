# NorthStar Apple Watch (watchOS)

**Current state: independently located SwiftUI source scaffold and reproducible XcodeGen project spec, not a shipped or embedded watch companion.** Screen is an explicit placeholder; workout capture, pairing, HealthKit entitlements and durable event storage are not enabled.

## Source ownership and packaging

`Sources/` is the single source of watch UI code. The `project.yml` declares a standalone watchOS **development target** for compiling and inspecting it on macOS. The eventual production target **must be referenced by or embedded into the Flutter iOS application's Xcode archive** under `apps/mobile/ios`, with matching approved bundle IDs, signing, entitlements and build phases. Do not duplicate the source into `apps/mobile/ios/Runner`.

On a Mac with Xcode and XcodeGen:

```sh
cd apps/watch_os
xcodegen generate --spec project.yml
xcodebuild -list -project NorthStarWatch.xcodeproj
# Inspect available watchOS simulators/SDKs before selecting a build destination.
```

The generated `NorthStarWatch.xcodeproj` from this standalone spec is **not** the embedded companion configuration. A later packaging PR must test actual iPhone + watch pairing and TestFlight archive. `Sources/` should remain the single source in both projects.

## Planned modules

- `Features/Workout/`: compact workout state, timer, sets; currently only informational UI
- `HealthKit/`: native background workout capture (unimplemented)
- `Connectivity/`: WatchConnectivity transport (unimplemented)
- `Persistence/`: watch-local transactional journal/outbox (unimplemented)

Read [ADR-0002](../../docs/adr/0002-watch-workout-architecture.md) and [watch-to-phone protocol](../../docs/SYNC_PROTOCOL.md). Do not claim support for an active recording session until native background/durability tests pass.
