# Wear OS companion — design

Status: draft for Adi's approval, 2026-11-27. Thread "Build the Wear OS app".
Reference implementation: the Apple Watch app (Phase 4 stages 2 to 5b,
[Phase 4 design](2026-11-26-phase-4-watch-and-tablet-design.md),
[ADR-0012](../../adr/0012-apple-watch-companion.md)).

## 1. Intent

Adi has a Samsung Galaxy Watch paired with an Android phone and wants BeyondRep
on it, with the same features the Apple Watch app has: a health glance, plans
and today's program workout, recording a strength workout on the watch, and the
live link with the phone in both directions. Android phone users get the same
watch experience as iPhone users, and the Android phone app finally gets real
device testing along the way.

## 2. Goals, non-goals, anti-goals

Goals

- Feature parity with the Apple Watch app as of stage 5b plus the watch's own
  health reads, delivered in five independently mergeable stages.
- Same rules as the Apple Watch: the watch never talks to the cloud, never sees
  the user id or email, the device that starts a session owns it, the phone
  imports a watch workout atomically and backs it up once.
- The same wire contract (`contracts/watch_link/v1`, `contracts/workout_sync/v2`)
  and the same golden cases, so Swift, Kotlin, Dart and the Python reference
  agree byte for byte.
- Installable by Adi from a Play testing track next to the phone app.

Non-goals (this phase)

- A standalone watch without a phone, or the watch signing in by itself.
- Tiles, complications and watch faces (possible later stage).
- Writing workouts to Health Connect (that is the Phase 5 thread).
- Samsung Health SDK or any Samsung-only API. Only public Wear OS APIs, so the
  app also runs on Pixel Watch and others.
- Flutter on the watch.

Anti-goals

- A watch screen that says "saved" before the watch's own database committed.
- Health values leaving the watch other than as decided in 4.3.
- Phone code paths that fork per watch platform beyond the transport bridge and
  labels; the Dart logic stays shared.

## 3. Constraints (from the repo)

- `apps/wear_os/` is a native Kotlin/Compose app with its own `AGENTS.md`:
  Health Services `ExerciseClient` plus a foreground service own recording;
  UI, session manager, persistence and transport stay separate; no Health
  Services permissions before the feature is built and tested.
- Today the shell uses `applicationId in.beyondrep.wear`. The Wear Data Layer
  only connects apps with **the same package name and signing certificate**, so
  the watch app must become `in.beyondrep.app` (the Play listing then shows one
  app with a phone and a watch build). Namespace `in.beyondrep.wear` stays.
- The phone app is Flutter, `compileSdk 37`, `minSdk 26`, app ID
  `in.beyondrep.app`. Its Dart watch code talks through the `WatchLink` and
  `WatchLiveLink` interfaces; the providers return the method-channel version
  only on iOS (`watch_link.dart:185`, `watch_live_link.dart:146`).
- New dependencies (`play-services-wearable` on the phone, Health Services,
  Wear Compose, a SQLite layer on the watch) need owner approval: approved by
  this design once Adi signs it off.
- Platform permissions and watch ownership changes need a numbered ADR (next
  ADR-0015 or later; ADR-0014 is taken by the Phase 5 Health Connect/Apple Health writer).
- The cloud container has Java and Gradle but no Android SDK. Builds run on the
  GitHub `wear_os` and `mobile` jobs; the Kotlin core is a plain JVM module so
  its tests also run locally.
- Play: several builds in one listing need distinct `versionCode`s. The phone
  Play job (`mobile-android-release`) has never run on hosted Codemagic; the
  `wear-os-*` Codemagic entries are failing templates.

## 4. Decisions

### 4.1 Approach (my call, explained to Adi 2026-11-27)

Native Kotlin + Jetpack Compose for Wear OS (Material 3 for Wear), with a
pure-Kotlin core module that ports `BeyondRepWatchCore`.

Considered and dropped:

- **Flutter on the watch**: weak support for rotary input/bezel, ambient mode,
  ongoing activity and Health Services; the roadmap asked to validate it and the
  answer for a workout recorder is no.
- **Kotlin Multiplatform core shared with the Apple Watch**: the Swift core is
  done and tested; rewriting it in KMP for the watch only buys nothing, and the
  golden cases already pin behaviour across languages.

### 4.2 Stages (my call, shown to Adi 2026-11-27)

1. **Watch core.** App ID change, `:core` JVM module, codecs, replay, state
   builder, completed builder, command applier, session machine, rest clock,
   journal; all golden cases and fixtures pass. No UI change beyond the
   placeholder text. CI runs `:core:test` and the debug build.
2. **Link and glance.** Phone Android Data Layer bridge (Kotlin in
   `apps/mobile/android`) behind the existing `WatchLink`; account binding,
   plans and health snapshots, acks, wipe; watch Home and Train pages with
   detail screens; phone watch status (banner, footer, Account & sync section)
   for Wear OS; Codemagic jobs so Adi can install both builds from a Play
   internal testing track.
3. **Workout recording.** Health Services exercise session in a foreground
   service with an ongoing activity, set logging with the rotating bezel/crown,
   rest timer with haptics, durable journal, `completed_workout` sent until the
   phone's `ack`; the phone importer (stage 4a) imports it; history tag;
   heart rate and calories through Health Connect per 4.3 (or stage 3b).
4. **Live link both ways.** The equivalents of 5a (watch owns, phone mirrors and
   sends commands) and 5b (phone owns, watch follows and sends commands).
5. **Watch's own health.** Steps and current heart rate the watch reads itself
   through Health Services passive monitoring, before a phone sync. Health
   Services has no sleep, HRV or resting heart rate history, so those tiles
   keep the phone's values; steps take the larger value as on the Apple Watch.
   The sleep/HRV golden cases do not apply to Kotlin. (My call.)

Each stage gets its own plan, built by one Sonnet agent with test-driven
development, reviewed by Opus, fixed, and opened as a PR for Adi.

### 4.3 Heart rate and calories of a watch workout (Adi chose C, 2026-11-27)

On the Apple Watch the phone reads them from Apple Health by the shared
`HKWorkout` UUID and stores nothing. Wear OS has no Health Connect on the watch
and no store shared by watch and phone for our app's session. Adi chose:
**the phone writes the watch workout, with its heart rate and calories, into
Health Connect, and reads them back from there**, like Apple Health.

- The watch records heart rate samples and active calories through Health
  Services and keeps them in its journal next to the session.
- After the phone has imported the workout (stage-4a `ack`), the watch sends a
  new `workout_health` message (workout id, heart rate samples, total active
  calories, start and end). This is the one message besides `health_snapshot`
  allowed to carry health values; the contract test is extended to allow it.
- The phone writes an `ExerciseSessionRecord` with its `HeartRateRecord` and
  `ActiveCaloriesBurnedRecord`, `clientRecordId` = workout id so a resend is
  deduplicated, stores only the Health Connect record id in the existing watch
  receipt, and acks. It never writes the values to ObjectBox, the outbox,
  Supabase, exports or logs; they live only in memory for the write.
- Without Health Connect write permission (or Health Connect missing), the
  phone acks `not_written`; the watch drops the samples and the phone shows no
  heart rate for that workout. The watch's own summary screen shows them in
  either case.
- History detail reads them fresh through the stored record id, the way
  `readOwnWorkout` does on iOS. The outside-workouts reader (ADR-0011) must hide
  sessions whose record id is in a receipt or whose data origin is our app.
- This needs the Health Connect write permissions the Phase 5 thread ("Save
  workouts to Apple Health") is adding (`WRITE_EXERCISE`, `WRITE_HEART_RATE`,
  `WRITE_ACTIVE_CALORIES_BURNED`) and an ADR amendment to ADR-0012 decision 4 and
  HEALTH_DATA.md (health values in transit watch → phone → Health Connect). Stage
  3 builds on that thread's writer and dedup receipts instead of a second one;
  if it has not landed, stage 3 ships recording with the watch summary only and
  a stage 3b adds `workout_health`.

Builder-check answers (my calls, flagged to Adi):

- **Consent:** the write follows the same "save workouts to Health Connect"
  choice the Phase 5 work adds. With it off, the phone acks `not_written` and
  shows no heart rate for that workout; writing into someone's health store
  without that choice would surprise them. If Phase 5 does not cover Android,
  stage 3b builds the one Android Health Connect writer and its receipts
  itself, to be reused by Phase 5, never a second one.
- **Phase 5 shape (from that thread, 2026-11-27):** writer
  `lib/features/health/data/health_workout_writer.dart` (Android
  `ExerciseSessionRecord`, `clientRecordId` = workout id, `clientRecordVersion`
  = revision), receipt `HealthExportReceiptEntity`, exporter
  `lib/features/health/application/workout_health_export.dart`. It exports only
  `northstar_phone` workouts and does not request `WRITE_HEART_RATE` or
  `WRITE_ACTIVE_CALORIES_BURNED`: stage 3 adds those permissions, extends the
  write input with optional heart rate samples and calories, and adds the
  `beyondrep_watch` rule to the exporter.
- **Retention on the watch:** samples and calories sit in the journal only
  with their session, and are deleted on the phone's `workout_health` ack, on
  the wipe, on `account_cleared`, when the binding is dropped, and at the
  latest 7 days after the workout ended, whichever comes first. They are never
  logged. The ADR amendment states this.
- **Phone-owned workouts (stage 4):** the following watch runs a Health
  Services session too and sends `workout_health` keyed by the phone's
  workout id, so phone-started workouts also get heart rate. The phone adds it
  to the same Health Connect session the Phase 5 writer makes for that
  workout (one session per workout). This replaces `workout_link` on Wear.

### 4.4 History label (my call)

Cloud origin stays `beyondrep_watch` for both watches (no migration). The local
tag says "Apple Watch" on iOS and "Watch" on Android, because an iPhone pairs
only with an Apple Watch and an Android phone only with Wear OS. A workout
restored on the other platform shows the other label; acceptable.

### 4.5 Contract changes (my call)

Additive only, `schema_version` stays 1. Behaviour that differs only on Wear
(for example how the follower is started) is tested in Kotlin, not added to the
shared cases, unless a message changes. `completed_workout` from Wear omits
`healthkit_workout_uuid` (already optional). The `workout_link` message (5b) has
no Wear meaning without a shared store and is not sent by Wear in this phase.
Anything else new gets fixtures, the Python test, Dart and Swift in the same PR.

## 5. Design

### 5.1 Watch app structure

```
apps/wear_os/
  core/            pure Kotlin/JVM: contracts, session, link, glance, store logic
  app/             Android: Compose UI, Health Services, Data Layer, wiring
```

- `core` mirrors `BeyondRepWatchCore` file for file where it makes sense
  (`StrictJson`, `WatchMessage`, `WorkoutEventV2`, `WorkoutReplay`,
  `SessionStateBuilder`, `CompletedWorkoutBuilder`, `CommandApplier`,
  `FollowerSession`, `SessionMachine`, `RestClock`, `WorkoutCursor`,
  `GlanceState`, `SyncLine`, `PhoneInbox`, `AckBuilder`, `WatchJournal`).
  JSON through `kotlinx.serialization` `JsonElement` with explicit unknown-key
  rejection. Tests read `../../contracts/**` directly.
- **Journal (my call, revised while planning):** SQLite behind a small
  `SqlDatabase` interface in `core` (like `SQLiteDatabase.swift`), with
  `sqlite-jdbc` in JVM tests and an `android.database.sqlite` adapter in the
  app. The journal's SQL is ported from `WatchJournal.swift` almost verbatim,
  same tables and semantics (binding, snapshots, sessions, events, outbox,
  tombstones, command ids), one transaction per user action. SQLDelight and
  Room were the alternatives; the thin interface adds no runtime dependency
  and keeps the Swift SQL recognisable.
- Stage 1 ports contracts, session, journal, inbox and ack; `Glance/*` moves
  with the screens to stage 2 and `FollowerSession` to stage 4.
- `minSdk 30` (Wear OS 3, Galaxy Watch4 and newer), `targetSdk`/`compileSdk`
  the newest the dependencies need, matching the phone where possible.
- `<meta-data com.google.android.wearable.standalone = false>` stays: the app
  needs the phone.

### 5.2 Phone ↔ watch link (Wear Data Layer)

Mapping of the WatchConnectivity calls the Dart code already uses:

| Dart `WatchLink` call | iOS today | Android |
|---|---|---|
| `updateContext` (latest per type) | application context | one `DataItem` per type at `/context/<type>`, replaced each time; empty map deletes them |
| `transfer` (guaranteed, queued) | `transferUserInfo` | a `DataItem` at `/queue/phone/<message_id>`; the receiver deletes it after handling |
| `isReachableForUpdates` / `status` | `isPaired`, `isWatchAppInstalled`, `isReachable` | `NodeClient` connected nodes and `CapabilityClient` capability `beyondrep_watch_app` declared by the watch |
| live messages (`WatchLiveLink`) | `sendMessage`, HK mirroring | `MessageClient` to the capable node; no queue, like `sendMessage` |
| `messages` stream (watch → phone) | delegate callbacks | `/queue/watch/<message_id>` items and live messages |

- The phone bridge is a Kotlin class registered in `MainActivity` on the same
  channel names (`beyondrep/watch_link`, the live channel). The provider gates
  become "iOS or Android".
- Messages from the watch that arrive while the Flutter app is not running stay
  as `DataItem`s; on start and on `onDataChanged` the bridge hands every pending
  item to Dart, and deletes one only after Dart says it was handled (the ack
  rule still lives in Dart). No `WearableListenerService` starting a Flutter
  engine in stage 2 (my call; revisit for stage 4 live sessions if the phone
  must wake).
- The watch side mirrors this in `app/link/`, with `WearableListenerService`
  for wake-up, writing into the journal before acking.
- Data Layer payloads are limited (100 KB per item); `plans_snapshot` must stay
  under it. The builder adds a size check with a test.

### 5.3 Accounts

Exactly ADR-0012 decision 5: the same HMAC account key, the phone imports only
matching workouts, sign out sends `account_cleared`, deletion sends the wipe
and resends it until acked, the watch drops a binding silent for 90 days.

### 5.4 Watch screens (Compose for Wear OS, Material 3)

Same information as the Apple Watch, in Wear patterns, Performance V2 colours:

- **Home:** readiness ring hero and 2×2 tiles with "vs usual" lines, sync line;
  tap opens the detail screens (readiness, sleep, trends).
- **Train:** today's program workout first, then plans, then quick workout.
  Home and Train are two vertical pages; scroll with the bezel/crown.
- **Workout (stage 3):** current set (exercise, set n of m, weight × reps,
  rotary to adjust the focused value, RPE, Log), rest page, overview page
  (time, live HR, sets). Ongoing activity chip on the watch face; ambient mode
  dims and updates once a minute.
- Round small and large screens, font scaling, TalkBack, reduced motion.

### 5.5 Workout recording (stage 3)

Health Services `ExerciseClient` with `ExerciseType.STRENGTH_TRAINING`
(fallback `WEIGHTLIFTING` if unsupported), data types heart rate and calories
if the device supports them, inside a foreground service of type `health` with
an `OngoingActivity`. Permissions: `BODY_SENSORS` (or the Wear OS 6
`READ_HEART_RATE`), `ACTIVITY_RECOGNITION`, `FOREGROUND_SERVICE_HEALTH`, plus
`POST_NOTIFICATIONS`. Denied heart rate: the workout still logs and HR shows
"—". The journal is the authority; the exercise session is only for sensors
and keeping the app alive. Process death: on restart the service finds the
active session in the journal and Health Services' current exercise and
reattaches, or ends the sensor session and keeps the logged sets (same orphan
policy as `OrphanSessionPolicy.swift`).

### 5.6 Live link (stage 4)

As Phase 4 5.6 and ADR-0012 stages 5a/5b, with `MessageClient` as the live
transport. When the phone starts a workout and the watch app is installed, the
phone sends a start message; the watch shows a notification/opens the follower
(Wear OS cannot launch an app silently the way `startWatchApp` does; exact
mechanism left to the stage-4 plan).

### 5.7 Distribution

- Watch `applicationId in.beyondrep.app`, its own `versionCode` range (for
  example phone code + 1 or a fixed offset; the stage-2 plan picks one and adds
  a test), same upload key as the phone. Play App Signing re-signs both with the
  same app key, so the Data Layer matches.
- Codemagic: turn the `wear-os-release` template into a manual job that builds
  the AAB signed with the upload key and drafts it to the same internal testing
  track, using the same groups as `mobile-android-release`
  (`ns_google_play`). Owner actions (outside Git): add the Wear OS form factor in
  Play Console, accept the Wear OS review rules.
- Debug sideloading of both builds works only when both are signed with the
  same debug key (built on one machine).

## 6. Testing

- `core`: JVM unit tests on every golden case and fixture (replay,
  session_state, completed, health, valid/invalid messages), journal crash
  safety (transaction rollback, duplicate delivery, wrong account).
- `app`: Robolectric/Compose tests where practical; build on CI.
- Phone: Dart tests for the provider gate and Android labels; Kotlin unit tests
  for the bridge's mapping logic kept free of Play services types where
  possible.
- Contracts: `tool/test_*.py` unchanged or extended when fixtures change.
- Device (Adi, Galaxy Watch + Android phone): a Wear OS section in
  `docs/RELEASE.md` per stage. Nothing is called device-verified until run.

## 7. Left to the builder

Compose layouts within 5.4, rotary step sizes, haptic patterns, journal table layout, Kotlin package names, the bridge's channel method shapes (must
match the iOS ones Dart already calls), the versionCode scheme.

## 8. Risks

- Samsung's Health Services support for strength training data types varies by
  model; must be checked with `getCapabilities` and on Adi's watch.
- The Android phone app has had no real-device testing; stage 2 may surface
  phone-side Android bugs first.
- Play Console Wear OS review and the never-run Codemagic Android job may need
  a round of fixes before Adi can install anything.
- Battery: the foreground service must stop at finish or discard; checked on
  device in a 60–90 minute session.
