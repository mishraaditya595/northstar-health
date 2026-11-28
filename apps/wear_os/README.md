# BeyondRep Wear OS

A **native Kotlin/Jetpack Compose watch application**. Stage 2 shows what the paired Android phone sends over the Wear Data Layer: Home (energy ring, four health tiles, sync line) and Train (today's program workout and plans, read-only previews), with detail screens. No Health Services session, workout recording, Start button or physiological data collection exists yet (stage 3).

Build requirements: JDK 17, Android SDK 35, Gradle 8.11.1, Android Gradle Plugin 8.9.2.

```sh
cd apps/wear_os
./gradlew :core:test :app:testDebugUnitTest :app:assembleDebug
```

Layout:

- `core/` is a pure Kotlin/JVM library (no `android.*`) that ports `apps/watch_os/Packages/BeyondRepWatchCore`: wire codecs, workout replay, journal, session machine and command applier. Its JUnit tests read `contracts/**` from disk and run every shared fixture and golden case.
- `app/` is the Wear OS application (Compose UI in `ui/`, the Data Layer link in `link/`, Android SQLite adapter). It depends on `core`. Its unit tests (Robolectric and Compose UI tests) need the Android SDK and run on CI.

On a machine without an Android SDK run only the core tests: `./gradlew :core:test -Pbeyondrep.coreOnly=true` (the switch leaves `:app` out of the build).

The watch `applicationId` is `in.beyondrep.app`, the same as the phone app: the Wear Data Layer only connects apps with the same package name and signing certificate. The Kotlin namespace stays `in.beyondrep.wear`.

The committed Gradle Wrapper should be generated from trusted Gradle tooling during bootstrap; **do not install an unreviewed wrapper JAR**. Running Wear OS builds from the Flutter `apps/mobile/android` Gradle project is not supported.

Future implementation: Kotlin `ExerciseClient` with a correctly configured foreground workout service, Room or equally tested watch-local transaction log, Wearable Data Layer transport with durable phone ACK and offline retry, wrist-down/low-power/rotary UI tests. Package/bundle IDs are **development placeholders**; set final Play identity/signing before publication.

See ../../contracts/workout_sync/v1/README.md.
