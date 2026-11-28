# Wear OS stage 3a: workout recording — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (Adi's choice for this project: one Sonnet agent runs the whole plan with strict TDD, then an Opus review). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Galaxy Watch starts a plan, today's program workout or a quick workout, logs sets with the bezel/crown, rests with a haptic, keeps a Health Services exercise session alive in a foreground service, and sends the finished `completed_workout` to the phone until the phone's `ack`.

**Architecture:** `:core` already has the whole session logic (`WorkoutController`, `SessionMachine`, `RestClock`, `CompletedWorkoutBuilder`, `OrphanSessionPolicy`, journal outbox and `applyAck`). This stage adds three small pure helpers to `:core`, then the app layer: a `ExerciseSensors` port over Health Services, a `WorkoutRunner` that drives controller + sensors + foreground service from the journal thread, an `OutboxFlusher` that puts queued workouts on `/beyondrep/queue/watch/`, and the Compose workout screens. The phone importer (iOS stage 4a) is platform-neutral and already imports Wear workouts; the phone only gets a test.

**Tech Stack:** Kotlin, Compose for Wear OS Material3 1.5.0, Health Services `androidx.health:health-services-client`, `androidx.wear:wear-ongoing`, `androidx.wear:wear` (ambient), Robolectric + Compose UI tests, JVM tests in `:core`, Flutter for the phone test.

**Spec:** `docs/superpowers/specs/2026-11-27-wear-os-companion-design.md` (sections 4.2 stage 3, 4.3, 5.4 Workout, 5.5). Parity reference: `apps/watch_os/Sources/App/AppModel.swift` (start, restore, finish, `summaryStatus`, rest haptic) and `apps/watch_os/Sources/Features/Workout/*.swift`.

**Scope split (my call):** the spec's stage 3 is split. **3a (this plan)** records and delivers the workout; heart rate and calories are shown live and on the watch summary from memory only, never stored or sent. **3b (next plan)** adds the `workout_health` message, the journal retention of samples (7 days), and the phone's Health Connect write through the Phase 5 writer (spec 4.3).

## Global Constraints

- Watch `applicationId` `in.beyondrep.app`, `minSdk 30`, `targetSdk 35`, `compileSdk 35`. Do not raise targetSdk (Wear OS 6 replaces `BODY_SENSORS` with `android.permission.health.READ_HEART_RATE` at targetSdk 36).
- Exercise type `ExerciseType.STRENGTH_TRAINING`, fallback `ExerciseType.WEIGHTLIFTING` when the device's capabilities lack it. Data types `DataType.HEART_RATE_BPM` and `DataType.CALORIES_TOTAL`, each only if supported. No GPS, no auto-pause.
- Foreground service type `health`; manifest permissions `BODY_SENSORS`, `ACTIVITY_RECOGNITION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_HEALTH`, `POST_NOTIFICATIONS`, `VIBRATE`, `WAKE_LOCK`.
- The journal is the authority. The Health Services session exists only for sensors and to keep the process alive. A logged set is shown as saved only after the journal commit.
- Heart rate and calories: memory only in 3a. Never in the journal, the outbox, a message, a log line, a crash string or a notification text.
- Denied or unsupported heart rate: the workout still records; heart rate shows "—", never 0; the summary omits the row.
- Everything that touches the journal runs on `WatchGraph.dispatcher` (single serial owner).
- `completed_workout` from Wear omits `healthkit_workout_uuid` (`queueCompleted(null)`).
- Copy: Android wording says "phone", not "iPhone". Summary status strings: `Saved to phone`, `Saved on watch · sent to phone`, `Saved on watch · waiting for phone`. Sign-in prompt unchanged from stage 2.
- Haptic: one vibration per rest deadline, scheduled from the deadline; none for a deadline already past at relaunch (same rule as `AppModel.swift` `hapticDeadline`).
- Device id: `"watch-" + UUID` lowercased, created once and kept in `SharedPreferences` key `watchInstallationId`.
- No new phone dependency, no contract change, no ObjectBox change. The Android code compiles and tests only on GitHub CI (no Android SDK in the cloud container); say so in the PR.
- Public repo: synthetic data only; never commit keystores, `key.properties`, `local.properties`.

## Review Focus

1. **Another app's exercise is running when Start is tapped** (Samsung Health workout). Expect: nothing is started, the watch says "Another workout app is recording. End it there first.", no journal session is created. Test in Task 4.
2. **Heart rate permission denied, or the device lacks the data type.** Expect: the workout starts and records, the overview shows "—", the summary has no heart rate row. Tests in Tasks 4 and 5.
3. **Process death mid-workout** (system kills the app, watch reboots). Expect: on the next launch the session is restored from the journal; if Health Services still reports our exercise, the runner reattaches; if not, it starts a new sensor session; a finished-but-unqueued session of any account is queued. Test in Task 4.
4. **Phone away for days with several workouts waiting.** Expect: every workout stays in the journal and is put again when the phone is reachable; the watch-queue pruner never deletes a `completed_workout`. Tests in Tasks 1 and 3.
5. **Sign-out or account switch on the phone mid-workout.** Expect: the active session of the cleared account is discarded (nothing sent), sensors end, the service stops, the watch shows the sign-in screen; another account never sees it. Test in Task 4.

---

### Task 1: `:core` link helpers — prune only acks, list what to put

**Files:**
- Modify: `apps/wear_os/core/src/main/kotlin/in/beyondrep/wear/core/link/WatchQueuePruner.kt`
- Create: `apps/wear_os/core/src/main/kotlin/in/beyondrep/wear/core/link/OutboxSender.kt`
- Test: `apps/wear_os/core/src/test/kotlin/in/beyondrep/wear/core/link/WatchQueuePrunerTest.kt`, `.../link/OutboxSenderTest.kt`

**Interfaces:**
- Produces: `object OutboxSender { fun toPut(pending: List<WatchMessage>, present: Set<String>): List<Pair<String, String>> }` returning `(DataLayerPaths.watchQueue(message.messageId), message.encode())` for each pending message whose path is not in `present`, oldest first. Use the existing encode method name on `WatchMessage`.

- [ ] **Step 1: Failing tests.** `WatchQueuePrunerTest.neverPrunesACompletedWorkout`: 25 items, 22 acks and 3 `completed_workout` (one 30 days old) → `stalePaths` lists only ack paths (the 2 oldest acks beyond 20) and none of the 3 workouts. `.undecodableItemsAreStillPruned` keeps passing. `OutboxSenderTest.putsOnlyWhatIsMissing`: two pending, one path present → one pair, for the missing one. `.keepsJournalOrder`: three pending, none present → paths in input order. `.emptyWhenAllPresent`.
- [ ] **Step 2:** `cd apps/wear_os && ./gradlew :core:test -Pbeyondrep.coreOnly=true --tests '*WatchQueuePrunerTest*' --tests '*OutboxSenderTest*'` → FAIL.
- [ ] **Step 3:** Pruner: only items whose JSON `type` is `ack` (or undecodable) are candidates; update its KDoc. Implement `OutboxSender.toPut`.
- [ ] **Step 4:** Same command → PASS; then full `:core:test` → PASS.
- [ ] **Step 5:** Commit `feat(wear-core): keep queued workouts out of the ack pruner, list outbox puts`.

### Task 2: `:core` session helpers — heart rate tracker and summary

**Files:**
- Create: `apps/wear_os/core/src/main/kotlin/in/beyondrep/wear/core/session/HeartRateTracker.kt`, `.../session/WorkoutSummary.kt`
- Test: `.../session/HeartRateTrackerTest.kt`, `.../session/WorkoutSummaryTest.kt`

**Interfaces:**
- Produces: `class HeartRateTracker { fun add(bpm: Double, at: Instant); val current: Int?; val average: Int?; fun reset() }` (memory only). `current` is the latest valid sample; the UI hides it when the sensor reports `Unavailable`. Valid means 1 to 250 bpm.
- Produces: `data class WorkoutSummary(val sessionId: String, val name: String, val elapsed: Duration, val sets: Int, val averageHeartRate: Int?, val totalCalories: Int?)` with `companion object { fun of(controller: WorkoutController, endedAt: Instant, averageHeartRate: Int?, totalCalories: Int?): WorkoutSummary }` with `sets = state.completedSets`, `elapsed = endedAt - startedAt` minus paused time if `WorkoutController` exposes it (match the Swift `WorkoutSummary` in `AppModel.swift`).

- [ ] **Step 1: Failing tests.** `HeartRateTrackerTest.ignoresZeroNegativeAndAbove250` (0, -1, 251 ignored; `average` null with no valid sample). `.averageRoundsHalfUp` (samples 70, 71 → 71). `.resetClears`. `WorkoutSummaryTest.countsCompletedWorkingSets` (3 logged, 1 warm-up → 3, per `completedSets`). `.keepsMissingHealthNull` (null inputs → null fields, never 0).
- [ ] **Step 2:** Run those tests → FAIL. **Step 3:** Implement. **Step 4:** PASS + full `:core:test`. **Step 5:** Commit `feat(wear-core): heart rate tracker and workout summary`.

### Task 3: App — `OutboxFlusher` and ack handling

**Files:**
- Create: `apps/wear_os/app/src/main/java/in/beyondrep/wear/link/OutboxFlusher.kt`
- Modify: `apps/wear_os/app/src/main/java/in/beyondrep/wear/app/WatchGraph.kt`, `.../link/LinkListenerService.kt`, `.../link/PhoneReachability.kt`, `.../WearMainActivity.kt`
- Test: `apps/wear_os/app/src/test/java/in/beyondrep/wear/link/OutboxFlusherTest.kt`

**Interfaces:**
- Consumes: `OutboxSender.toPut`, `WatchJournal.pendingCompleted(limit)`, `DataItems` (`put`, `all`).
- Produces: `class OutboxFlusher(items: DataItems, journal: WatchJournal, dispatcher: CoroutineDispatcher) { suspend fun flush() }` — reads up to 50 pending on the journal dispatcher, lists `items.all(WATCH_QUEUE_PREFIX)` paths, puts the missing ones. Errors other than cancellation are swallowed (the next trigger retries). `WatchGraph.outbox: OutboxFlusher`.
- Triggers: activity `onStart`, `catchUp()` completion, phone reachability turning true, and right after `WorkoutRunner` queues a workout (Task 4).
- The phone's `ack` for a workout already reaches `journal.applyAck` through `PhoneInbox`; after it `graph.bump()` runs (stage 2 `onApplied`), so the summary status updates. No code change there; the test pins it.

- [ ] **Step 1: Failing tests** (Robolectric, reuse the `FakeItems` pattern from `DataLayerLinkTest.kt`, in-memory journal via `WatchGraph(context, "test-${UUID}.db")`): `flushPutsAQueuedWorkoutOnce` (queue one via `WorkoutController.start` + log + `markCompleted` + `queueCompleted(null)`; flush twice → one put at `/beyondrep/queue/watch/<message_id>`). `flushPutsAgainWhenThePhoneDeletedItWithoutAck`. `ackDeliversAndStopsResending` (route a phone `ack` with result `stored` through `graph.link.onChanges` → `journal.delivery(sessionId) == "delivered"`, a later flush puts nothing). `aFailingPutIsRetriedOnTheNextFlush`.
- [ ] **Step 2:** `./gradlew :app:testDebugUnitTest --tests '*OutboxFlusherTest*'` (CI only: push and read the `wear_os` job) → FAIL.
- [ ] **Step 3:** Implement and wire the triggers.
- [ ] **Step 4:** PASS on CI. **Step 5:** Commit `feat(wear): send queued workouts to the phone until acked`.

### Task 4: App — `ExerciseSensors`, `WorkoutRunner`, foreground service

**Files:**
- Create: `apps/wear_os/app/src/main/java/in/beyondrep/wear/exercise/ExerciseSensors.kt` (port + `HealthServicesSensors`), `.../exercise/WorkoutService.kt`, `.../workout/WorkoutRunner.kt`, `.../workout/RestHaptics.kt`
- Modify: `apps/wear_os/app/build.gradle.kts`, `apps/wear_os/app/src/main/AndroidManifest.xml`, `.../app/WatchGraph.kt`
- Test: `apps/wear_os/app/src/test/java/in/beyondrep/wear/workout/WorkoutRunnerTest.kt` (with `FakeSensors` and `FakeServiceControl` in the test source set)

**Interfaces:**
- `interface ExerciseSensors { suspend fun owner(): ExerciseOwner; suspend fun start(): SensorStart; suspend fun pause(); suspend fun resume(); suspend fun end(); val readings: Flow<SensorReading> }`
- `enum class ExerciseOwner { NONE, OURS, OTHER_APP }` (from `getCurrentExerciseInfoAsync().exerciseTrackedStatus`).
- `data class SensorStart(val heartRate: Boolean, val calories: Boolean)` — what the device supports and the user allowed.
- `sealed interface SensorReading { data class HeartRate(val bpm: Double, val at: Instant); data class Calories(val total: Double); data object Unavailable }`
- `interface ServiceControl { fun startForeground(); fun stop() }` — `WorkoutService` implements it via `ContextCompat.startForegroundService` with an `OngoingActivity` (status text: workout name and set count, no health values) and `stopSelf`.
- `class WorkoutRunner(graph: WatchGraph, sensors: ExerciseSensors, service: ServiceControl, clock: () -> Instant, deviceId: String, timeZone: () -> String)`:
  - `val state: StateFlow<RunnerState>` where `RunnerState` is `Idle`, `Blocked(reason: String)`, `Running(controller: WorkoutController, heartRate: Int?, calories: Int?, hrAvailable: Boolean)`, `Finished(summary: WorkoutSummary)`.
  - `suspend fun start(template: WorkoutTemplate)`: requires a binding (`journal.binding()`), no running session; `OTHER_APP` → `Blocked("Another workout app is recording. End it there first.")`, no journal write; else `WorkoutController.start(...)` with the binding's `unit`, then `sensors.start()`, then `service.startForeground()`.
  - `log`, `setRpe`, `skip`, `extendRest`, `skipRest`, `pause`/`resume` (also pause/resume sensors), `addSet`, `addExercise`, `focus`: delegate to the controller on the journal dispatcher and bump.
  - `suspend fun finish()`: `markCompleted()`, `sensors.end()`, `queueCompleted(null)`, `graph.outbox.flush()`, `service.stop()`, `Finished(summary)` with the tracker's average and calories.
  - `suspend fun discard()`: `discard()`, `sensors.end()`, `service.stop()`, `Idle`.
  - `suspend fun restore()`: queue `pendingFinishAllAccounts` via `queuePendingFinish`; restore the bound account's active session; `owner()` `OURS` → reattach readings, `NONE` → `sensors.start()`, `OTHER_APP` → keep recording without sensors; start the service. `OrphanSessionPolicy` decides discards as in `AppModel.swift`.
  - Account change: observe `graph.revision`; when the bound account is gone or differs from the running session's, discard as above (journal `clearAccount` has already removed or kept rows per stage 2).
- `RestHaptics`: one `Vibrator` pulse at the deadline from `controller.restDeadline`, rescheduled when the deadline changes, skipped if already past at schedule time.
- Dependencies: `androidx.health:health-services-client:1.0.0` (bump to a newer stable only if CI cannot resolve it or an API above is missing), `androidx.wear:wear-ongoing:1.0.0`, `androidx.core:core-ktx` if not present, `org.jetbrains.kotlinx:kotlinx-coroutines-guava:1.10.2` for `ListenableFuture.await()`.

- [ ] **Step 1: Failing tests** in `WorkoutRunnerTest`: `startCreatesSessionStartsSensorsAndService`; `anotherAppsExerciseBlocksStartWithoutAJournalSession` (Review Focus 1); `deniedHeartRateStillRecords` (`SensorStart(false, false)` → running, `heartRate == null`, `hrAvailable == false`; Review Focus 2); `finishQueuesFlushesStopsAndSummarises` (one put, `service.stopped`, summary sets == 1, average from fake readings 70/72 → 71); `finishWithoutHeartRateHasNullAverage`; `discardSendsNothing`; `restoreReattachesWhenOursIsRunning` and `restoreStartsSensorsWhenNoneIsRunning` (Review Focus 3: kill = new `WorkoutRunner` over the same db); `restoreQueuesAFinishedButUnqueuedSession`; `signOutMidWorkoutDiscardsAndStops` (apply `account_cleared` through `graph.link.onChanges`; Review Focus 5); `healthValuesNeverReachTheJournal` (after a finished workout with readings, no row of any journal table contains `"bpm"`, `"heart"` or `"calor"`, by querying `sqlite_master` table names and dumping rows).
- [ ] **Step 2:** Push, read the `wear_os` job → FAIL (compile or assertion).
- [ ] **Step 3:** Implement the port, runner, service, haptics; manifest `<service android:name=".exercise.WorkoutService" android:foregroundServiceType="health" android:exported="false" />` and the permissions in Global Constraints.
- [ ] **Step 4:** CI PASS (`:core:test :app:testDebugUnitTest :app:assembleDebug`). **Step 5:** Commit `feat(wear): record workouts with a Health Services session in a foreground service`.

### Task 5: App — workout screens and Start

**Files:**
- Create: `apps/wear_os/app/src/main/java/in/beyondrep/wear/ui/workout/WorkoutScreen.kt` (pager of Set, Rest, Overview), `SetPage.kt`, `RestPage.kt`, `OverviewPage.kt`, `ExercisesScreen.kt`, `RpePicker.kt`, `EndConfirmScreen.kt`, `SummaryScreen.kt`, `PermissionGate.kt`
- Modify: `.../ui/RootScreen.kt` (routes), `.../ui/TrainScreen.kt` (Start on Today and on each plan, `+ Quick workout`), `.../ui/PlanPreviewScreen.kt` (Start button), `.../ui/WatchViewModel.kt` (runner state, start/finish actions), `.../WearMainActivity.kt` (ambient observer, restore on create)
- Test: `apps/wear_os/app/src/test/java/in/beyondrep/wear/ui/WorkoutScreensTest.kt`; update `WatchScreensTest.trainHasNoStartButtonOrQuickWorkout` and `tappingAPlanOpensItsPreviewWithoutAStartButton` to the new behaviour.

**Interfaces:**
- Consumes: `WorkoutRunner.state` and its actions, `WorkoutController.cursor`, `SetInput` (step, clamp, displayWeight, grams), `RestClock`, `WorkoutSummary`.
- Copy (port of the Swift strings, "iPhone" → "phone"): `Start`, `+ Quick workout`, `Log set`, `Set N of M`, `Turn the crown · tap the other box to switch`, `RPE, optional`, `How hard was it?`, `Rest`, `+30 s`, `Skip`, `Not resting`, `Paused`, `Exercises`, `Add set`, `+ Add exercise`, `No recent exercises. Add them in BeyondRep on your phone.`, `All planned sets done`, `Next: <exercise> · set N of M`, `End`, `End workout?`, `Save workout`, `Keep going`, `Discard`, `Discard this workout? It is deleted from your watch.`, `No sets logged yet.`, `Done`, summary rows `Time`, `Sets`, `Heart rate` (`<n> avg`), and the three summary status strings.
- Rotary: `Modifier.onRotaryScrollEvent` + `focusRequester` on the focused value box of the Set page; step from `SetInput.step`, clamped by `SetInput.clamp`; scrolling lists keep `rotaryScrollable` defaults.
- Accessibility: content descriptions from the Swift `accessibilityLabel`s (`Rest, N seconds left`, `N of M sets`, `<exercise>, N of M sets done`, `RPE N`); heart rate tile reads `Heart rate <n> beats per minute` or `Heart rate not available`.
- `PermissionGate`: before the first Start, request `BODY_SENSORS`, `ACTIVITY_RECOGNITION`, `POST_NOTIFICATIONS` with `rememberLauncherForActivityResult(RequestMultiplePermissions())`; any denial still starts (Review Focus 2).
- Ambient: `AmbientLifecycleObserver` from `androidx.wear:wear:1.3.0`; in ambient the workout pages show a dimmed clock, set count and rest time, updated once a minute; no animation.

- [ ] **Step 1: Failing tests:** `trainShowsStartOnTodayAndPlansAndQuickWorkout`; `startOpensTheSetPage` (fake runner state); `rotaryAdjustsTheFocusedValueByTheUnitStep` (kg: +2.5 per detent via `performRotaryScrollInput`); `logSetShowsRestPageWithCountdown`; `overviewShowsDashWhenHeartRateUnavailable` (Review Focus 2); `endWithNoSetsOffersOnlyDiscard`; `summaryShowsHeartRateRowOnlyWhenKnown`; `summaryStatusSaysWaitingForPhoneWhenUnreachable`; `blockedStartShowsTheOtherAppMessage`; `largeFontScaleKeepsLogSetReachable` (font scale 1.3, scroll to `Log set`).
- [ ] **Step 2:** CI → FAIL. **Step 3:** Implement. **Step 4:** CI PASS. **Step 5:** Commit `feat(wear): workout screens and Start on Train`.

### Task 6: Phone — Wear workout arrives as a Watch workout

**Files:**
- Test: `apps/mobile/test/watch/watch_workout_inbox_test.dart` (add cases), `apps/mobile/test/progress/` history detail test file that covers the watch tag (find it with `grep -rln "Apple Watch" apps/mobile/test/progress`)

**Interfaces:** no production change expected. If a test fails, fix only what it shows and say so in the PR.

- [ ] **Step 1: Tests:** `a Wear completed_workout without healthkit_workout_uuid imports and acks stored` (synthetic fixture copied from `contracts/watch_link/v1/fixtures/valid/completed_workout*.json` with the uuid removed); `on Android the history detail of a watch workout shows the Watch tag and no heart rate row` (`debugDefaultTargetPlatformOverride = TargetPlatform.android`, `ownWorkoutHealthProvider` returns null for a null id).
- [ ] **Step 2:** `cd apps/mobile && flutter test test/watch/watch_workout_inbox_test.dart <history test>` → expect PASS on first run (they pin existing behaviour); if FAIL, fix minimally.
- [ ] **Step 3:** `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test` → all clean.
- [ ] **Step 4:** Commit `test(watch): Wear workouts import on Android`.

### Task 7: Docs

**Files:** `docs/adr/0015-wear-os-companion.md` (stage 3a amendment: permissions, foreground service type, heart rate and calories in memory only, split of 3b), `docs/HEALTH_DATA.md` (Wear live sensor reads, memory only), `docs/RELEASE.md` (new "Wear OS stage 3a: workout recording (device checks, none run)" table), `docs/ROADMAP.md`, `CLAUDE.md` (one status bullet in the style of the stage-2 bullet, stating "compiles and tests only on GitHub CI"), `apps/wear_os/AGENTS.md` if it lists permissions.

- RELEASE rows (all `not run`): first Start asks for sensors, activity and notifications; Start from Today, a plan and Quick workout; bezel/crown changes weight and reps by the unit step; Log set → rest page, one haptic at zero, screen off included; ongoing activity chip on the watch face returns to the workout; ambient dims and updates once a minute; app killed from recents mid-workout and reopened → same sets, still recording; heart rate denied → "—" and no summary row; Samsung Health workout running → the other-app message; finish with phone nearby → "Saved to phone" within a minute and the workout in phone history with the Watch tag; finish in airplane mode → "waiting for phone", delivered after reconnect, exactly once; sign out on the phone mid-workout → workout discarded, sign-in screen; 60–90 minute session battery drop noted and the service stops at finish or discard; whether Samsung Health or Health Connect shows a second copy of the session (input for 3b).
- [ ] **Step 1:** Write the docs. **Step 2:** `python3 -m unittest discover -s tool -p 'test_*.py'` → OK. **Step 3:** Commit `docs(wear): stage 3a recording, device checks`.

### Finish

- [ ] Full local checks: `:core:test -Pbeyondrep.coreOnly=true`, Flutter format/analyze/test, Python tool suite. CI green on all jobs.
- [ ] Push `claude/project-thread-otsdbl`; report test counts, what ran only on CI, and anything skipped.
