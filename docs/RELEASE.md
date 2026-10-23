# NorthStar release-readiness gates

**Status:** Structure and scaffolding only. Neither watch application nor the mobile app is ready for store distribution.

## Source and builds

- Mobile Flutter project rooted at `apps/mobile`, version-controlled Android and iOS runners plus `pubspec.lock`; no project generation in normal CI.
- Separate `apps/wear_os` APK build with committed official Gradle wrapper and Kotlin/Compose app.
- SwiftUI `apps/watch_os/Sources` is the single watch source; XcodeGen proof-target compiles only on macOS with Xcode/watchOS SDK. **An actual Apple Watch companion target embedded in the iOS Runner/Xcode workspace is still a blocker.**
- Mobile iOS Release archive with correct app ID, provisioning/signing, HealthKit entitlements only when health is implemented; validate launch and rotation on phones/iPads.
- Watch iOS embedding, companion bundle identifiers, signing, TestFlight archive/physical pairing and watch-only source experiment must not be confused.
- Wear OS uses final app identity/signing, Play Console declarations and physical round-watch layout tests; package IDs in scaffolding are placeholders.
- Keep FlutterWatch custom toolchain out of stable builds; experimental comparison only.

## Feature and privacy readiness

- ObjectBox real sessions/sets with generated model UID fixture migration, durable offline writes and recovery through process death.
- No Supabase backup until authenticated RLS, conflict resolution, tombstones and completed-workout-only payload allowlist are verified.
- No HealthKit/Health Connect reads or summary exports until permissions/consent, provenance, stale/denied, duplicate-platform-workout prevention and release policy review.
- No Firebase SDK collection until separate diagnostics/analytics default-off initialization, consent controls, redaction and synthetic leak tests.
- Watch set logging must persist locally and survive screen off, disconnect, battery constraints and reconnect before UI claims success; native sensors and workout lifecycle operate independently of UI. Two-stage ACK (watch->phone and phone->Supabase).

## Device validation

- Android low-memory device and current Android tablet in portrait/landscape, resizing; iPhone and iPad split view; dynamic text, talkback/voiceover and both themes.
- Apple Watch and Wear OS physical watch: real 60–90 minute workout, pause/resume/end, health permissions, workout summary ownership, power/battery/CPU profiling, offline log replay/duplicate handling, recovery after killed UI.
- Reproducible CI passes for contract fixtures, Flutter format/analyze/test/APK, Wear OS debug, macOS iOS/watchOS target builds.
- Distribution is gated by independent review and manual Apple/Google store smoke testing; passing unit tests alone never authorizes a release.

## Ordered engineering follow-ups

1. Integrate `apps/watch_os/Sources` with a **real existing-iOS-app watchOS target** inside `apps/mobile/ios` using Xcode; commit project settings, embedding/copy phase and test a companion archive.
2. Verify mobile iOS simulator and native watchOS build in macOS CI, then replace placeholder bundle identifiers with final approved organization IDs and signing configuration.
3. Implement transactional ObjectBox workout repo and mobile native adapters; only then add sensor/HealthKit/Health Services features.
4. Implement cloud backup and independent watch event queues against v1 protocol; add multi-device permission/reconnect and version migration tests.
