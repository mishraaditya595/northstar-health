# BeyondRep watch architecture: watchOS and Wear OS

**Status:** Apple Watch companion in progress per [ADR-0012](adr/0012-apple-watch-companion.md) (contracts, watch core, a read-only glance and the embedded companion target in source, none device-verified); Wear OS deferred. Native SwiftUI/Wear OS non-recording UI scaffolds exist under `apps/watch_os/` and `apps/wear_os/`. The Apple Watch app records workouts in source (stage 4b: native `HKWorkoutSession`/`HKLiveWorkoutBuilder`, durable journal, delivery to the phone until acked; one `HKWorkout` per session), not device-verified. Wear OS Health Services sessions remain unimplemented. Based on the attached “BeyondRep — Flutter Smartwatch Development Research” (23 October 2026). Revalidate current third-party compatibility immediately before any spike.

## Separate the three capabilities

1. Flutter mobile **reads** available Apple HealthKit/Android Health Connect metrics; this alone **does not require** a BeyondRep watch app, nor guarantee a watch's provider has synchronized everything.
2. A BeyondRep watch **UI** selects plans and logs sets. Flutter on Wear OS may be feasible; third-party FlutterWatch on watchOS remains experimental; native Compose/SwiftUI always available.
3. The watch **runs live background workouts** when wrist is down, screen off or Flutter UI is gone. That requires native OS services, not a widget timer or connectivity plugin.

## Required watch-first features

Pick pre-synced plan, start session, show exercise/set, edit reps and load, complete/correct set, pause/resume/end, count rest with haptics, show authorized live HR/elapsed time, and keep an offline journal while phone disconnected. Editing full plans and analytics stay on the phone. Watches must not depend on phone network to acknowledge a local save.

## Wear OS

Trial **Flutter UI** only with **Kotlin Health Services `ExerciseClient`** owning an active session, foreground service where required, background data collection, permissions and local persistence. Bridge stable typed commands/events to Dart. Compare start speed, memory, battery, screen-off continuity, ambient/rotary/touch behavior on actual watches against **Jetpack Compose for Wear OS**. If Flutter UI loses on reliability/compatibility/energy, production UI is Compose without changing mobile domain or sync protocol.

## Apple Watch

Stock Flutter does not officially target watchOS. `flutter_watchos` package is *not* an engine; `flutter-watchos` at flutterwatch.dev is a separate experimental engine/toolchain (research cites SDK pinned to Flutter 3.47.5, different from mobile's 3.47.7). Test its supported devices, account artifacts, plugin FFI, signing/TestFlight and distribution before relying on it. **Native SwiftUI fallback is production-default until spike passes.** A Swift HealthKit `HKWorkoutSession` + `HKLiveWorkoutBuilder` service owns workout lifecycle and sensors under appropriate permissions/background capabilities. FlutterWatch UI, if used, must not be responsible for workout continuity. Native Apple Watch companion can integrate with Flutter iOS through WatchConnectivity.

**Live workout on the phone (stage 5a, source only):** the watch owns a workout it starts and mirrors it to the phone (HealthKit workout mirroring, with `WCSession.sendMessage` as fallback); the phone shows the sets live and sends idempotent commands (log, skip, add a set, rest, pause, finish, discard). The phone stores nothing for it. Not released or device-verified; see `docs/RELEASE.md`.

**The watch joins a workout the phone owns (stage 5b, source only):** the phone launches the watch app (`startWatchApp`, no new phone permission) and its ObjectBox engine stays the only authority; the watch starts a HealthKit session, shows Set, Rest and Overview pages ("On your iPhone") and sends idempotent commands that show as saved only when the phone lists them as applied. The watch saves the one `HKWorkout` at finish and sends a `workout_link` (resent until the phone acks it); the phone stores a receipt, so history shows "From Apple Health" for it. It does not join when the watch has a session of its own or is bound to another account. Not released or device-verified; see `docs/RELEASE.md`.

**Do not assume ObjectBox Flutter library can run on watchOS**, particularly the custom engine; use platform-supported native on-watch persistence. iOS app holds its *own* ObjectBox cache.

## Data ownership and backend handoff

The watch owns its **recording session and local pending journal**, not the mobile database or cloud record. The phone is the first Supabase backup coordinator after a durable watch->phone ACK. Apple Watch sessions saved by the watch in HealthKit carry origin and external record references so phone **does not export a duplicate HKWorkout**. Wear OS uses exactly one designated health-platform writer, generally the Android phone. Raw heart-rate streams are not backed up to Supabase; only detailed BeyondRep workout sets become authenticated completed-workout backups. Watch local data survives phone disconnect but may be lost on watch reset before acknowledged; show pending sync state. See [ADR-0003](adr/0003-data-cloud-health.md), [SYNC_PROTOCOL](SYNC_PROTOCOL.md), and [CLOUD_SYNC](CLOUD_SYNC.md).

## Package decisions

- `health`: candidate for **phone** permissions / HealthKit and Health Connect; not a watch workout service.
- `watch_connectivity`: candidate cross-platform transport; not durable/exactly-once sync.
- `flutter_watch_link`: only for specific FlutterWatch/iPhone scenario; experimental.
- `flutter_workoutkit`: optional scheduling into Apple's Workout app, not logging BeyondRep strength sets.
- `flutter_watchos`: UI helpers usable only with approved custom watchOS runtime.
- No watch-specific runtime package added to `pubspec.yaml` until PoC validated.

## Physical device gates

- Real Apple Watch and Wear OS watch: install/release signing and 60–90 minute workout test.
- Screen off, exit foreground, return to watch face, interruptions, background permission revocation, app/activity recreation, phone disconnection.
- Heart-rate updates and pause/resume/end accurate; set edits saved to watch durable storage; no lost/duplicated operations after reconnect and restart.
- Measure CPU, battery, RAM, dropped frames/start latency against native baseline.
- Small round screen, rotaries/Digital Crown, large text, haptic feedback and accessibility tested.
- TestFlight and Play internal testing/package compatibility gate before choosing watch UI framework.

## Source and uncertainty

The attached research is a feasibility study, not a built watch prototype. Its custom watchOS engine compatibility, memory figures and supported device list were reported from maintainers, not independently measured. See research reference: https://github.com/flutterwatch/flutter-watchos and official https://developer.android.com/health-and-fitness/health-services/active-data and https://developer.apple.com/documentation/healthkit/running-workout-sessions.

## Repository entry points
- `apps/watch_os/Sources/`: SwiftUI UI preview, XcodeGen watch compile specification in `apps/watch_os/project.yml`. The target is embedded in `apps/mobile/ios/Runner.xcodeproj` by `tool/embed_watch_target.rb` (stage 3, built unsigned in CI, signing and device pairing not verified). Required for release.
- `apps/wear_os/app/`: Kotlin/Compose watch scaffold with watch manifest and independent Gradle build.
- `contracts/workout_sync/v1/`: versioned language-neutral schema and fictional event fixtures; real serializers not implemented.
- `experiments/`: evaluated only; no Flutter watch runtime committed into stable builds.

## Wear OS companion

The Wear OS app follows [ADR-0015](adr/0015-wear-os-companion.md): native Kotlin/Compose, the phone's app ID and signing key, the Wear Data Layer as transport, and the same ownership and backup rules as the Apple Watch. Stage 1 (the JVM watch core in `apps/wear_os/core`) is implemented in source and not device-verified; the Health Services recording described above remains unimplemented.
