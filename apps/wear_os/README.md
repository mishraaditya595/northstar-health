# NorthStar Wear OS

A **native Kotlin/Jetpack Compose watch application foundation**. The current activity displays a clearly labelled non-recording preview. No Health Services session, offline workout logger, wearable pairing or physiological data collection exists yet.

Build requirements: JDK 17, Android SDK 35, Gradle 8.11.1, Android Gradle Plugin 8.9.2.

```sh
cd apps/wear_os
./gradlew :app:assembleDebug
```

The committed Gradle Wrapper should be generated from trusted Gradle tooling during bootstrap; **do not install an unreviewed wrapper JAR**. Running Wear OS builds from the Flutter `apps/mobile/android` Gradle project is not supported.

Future implementation: Kotlin `ExerciseClient` with a correctly configured foreground workout service, Room or equally tested watch-local transaction log, Wearable Data Layer transport with durable phone ACK and offline retry, wrist-down/low-power/rotary UI tests. Package/bundle IDs are **development placeholders**; set final Play identity/signing before publication.

See ../../contracts/workout_sync/v1/README.md.
