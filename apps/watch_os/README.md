# BeyondRep Apple Watch (watchOS)

**Current state: a read-only glance (readiness, sleep, resting HR, HRV, steps, plan names) fed by the phone over WatchConnectivity, embedded in the iPhone Runner project, not shipped and not device-verified.** No workout capture, no HealthKit access or entitlement, no Start button.

## Source ownership and packaging

`Sources/` is the single source of watch UI code. The `project.yml` declares a standalone watchOS **development target** for compiling and inspecting it on macOS. The eventual production target **must be referenced by or embedded into the Flutter iOS application's Xcode archive** under `apps/mobile/ios`, with matching approved bundle IDs, signing, entitlements and build phases. Do not duplicate the source into `apps/mobile/ios/Runner`.

On a Mac with Xcode and XcodeGen:

```sh
cd apps/watch_os
xcodegen generate --spec project.yml
xcodebuild -list -project BeyondRepWatch.xcodeproj
# Inspect available watchOS simulators/SDKs before selecting a build destination.
```

The generated `BeyondRepWatch.xcodeproj` from this standalone spec is only a compile proof. The embedded companion is a second target named `BeyondRepWatch` inside `apps/mobile/ios/Runner.xcodeproj`, produced by `tool/embed_watch_target.rb` (Ruby `xcodeproj` gem, pinned in `tool/Gemfile`): it references the files in `Sources/` and `Packages/BeyondRepWatchCore/Sources/` by relative path, links `libsqlite3.tbd` and copies the app into `Runner.app/Watch` ("Embed Watch Content"). The script is idempotent. To regenerate: `git checkout apps/mobile/ios/Runner.xcodeproj/project.pbxproj && cd tool && bundle install && bundle exec ruby embed_watch_target.rb`. After adding or removing a watch Swift file, regenerate the same way. The `ios-with-watch` job in `watchos_smoke.yml` builds it unsigned. Real pairing and the TestFlight archive are still unverified. `Sources/` stays the single source in both projects.

## BeyondRepWatchCore package

`Packages/BeyondRepWatchCore/` is a pure Swift package (Foundation and system SQLite only) for the watch's message codecs, session state machine, event replay and on-watch journal ([ADR-0012](../../docs/adr/0012-apple-watch-companion.md)). It has no UI and no transport yet. It is tested against the shared files under `contracts/` (`workout_sync/v2`, `watch_link/v1`):

```sh
swift test --package-path apps/watch_os/Packages/BeyondRepWatchCore   # macOS
```

CI runs this in the `WatchOS standalone build proof` workflow before the Xcode build. The package's source files are compiled directly into the watch app target (as part of the app module, not as a linked package), so app code guards `import BeyondRepWatchCore` with `#if canImport`.

## Planned modules

- `Features/Home/`: the read-only glance; `Features/Workout/` (set logging) is not built yet
- `HealthKit/`: native background workout capture (unimplemented)
- `Connectivity/`: receives the phone's application context and user info (implemented, receive only)
- `Persistence/`: watch-local transactional journal/outbox (unimplemented)

Read [ADR-0002](../../docs/adr/0002-watch-workout-architecture.md) and [watch-to-phone protocol](../../docs/SYNC_PROTOCOL.md). Do not claim support for an active recording session until native background/durability tests pass.
