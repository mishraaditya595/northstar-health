# Northstar watch architecture: watchOS and Wear OS

**Status:** Research-backed architectural direction and future spikes; **no actual watch app implemented**. Based on the attached “NorthStar Health — Flutter Smartwatch Development Research” (23 October 2026). Revalidate current third-party compatibility immediately before any spike.

## Separate the three capabilities

1. Flutter mobile **reads** available Apple HealthKit/Android Health Connect metrics; this alone **does not require** a Northstar watch app, nor guarantee a watch's provider has synchronized everything.
2. A Northstar watch **UI** selects plans and logs sets. Flutter on Wear OS may be feasible; third-party FlutterWatch on watchOS remains experimental; native Compose/SwiftUI always available.
3. The watch **runs live background workouts** when wrist is down, screen off or Flutter UI is gone. That requires native OS services, not a widget timer or connectivity plugin.

## Required watch-first features

Pick pre-synced plan, start session, show exercise/set, edit reps and load, complete/correct set, pause/resume/end, count rest with haptics, show authorized live HR/elapsed time, and keep an offline journal while phone disconnected. Editing full plans and analytics stay on the phone. Watches must not depend on phone network to acknowledge a local save.

## Wear OS

Trial **Flutter UI** only with **Kotlin Health Services `ExerciseClient`** owning an active session, foreground service where required, background data collection, permissions and local persistence. Bridge stable typed commands/events to Dart. Compare start speed, memory, battery, screen-off continuity, ambient/rotary/touch behavior on actual watches against **Jetpack Compose for Wear OS**. If Flutter UI loses on reliability/compatibility/energy, production UI is Compose without changing mobile domain or sync protocol.

## Apple Watch

Stock Flutter does not officially target watchOS. `flutter_watchos` package is *not* an engine; `flutter-watchos` at flutterwatch.dev is a separate experimental engine/toolchain (research cites SDK pinned to Flutter 3.47.5, different from mobile's 3.47.7). Test its supported devices, account artifacts, plugin FFI, signing/TestFlight and distribution before relying on it. **Native SwiftUI fallback is production-default until spike passes.** A Swift HealthKit `HKWorkoutSession` + `HKLiveWorkoutBuilder` service owns workout lifecycle and sensors under appropriate permissions/background capabilities. FlutterWatch UI, if used, must not be responsible for workout continuity. Native Apple Watch companion can integrate with Flutter iOS through WatchConnectivity.

**Do not assume ObjectBox Flutter library can run on watchOS**, particularly the custom engine; use platform-supported native on-watch persistence. iOS app holds its *own* ObjectBox cache.

## Package decisions

- `health`: candidate for **phone** permissions / HealthKit and Health Connect; not a watch workout service.
- `watch_connectivity`: candidate cross-platform transport; not durable/exactly-once sync.
- `flutter_watch_link`: only for specific FlutterWatch/iPhone scenario; experimental.
- `flutter_workoutkit`: optional scheduling into Apple's Workout app, not logging Northstar strength sets.
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
