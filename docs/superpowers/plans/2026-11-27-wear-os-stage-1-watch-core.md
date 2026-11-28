# Wear OS stage 1: watch core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pure-Kotlin `:core` module in `apps/wear_os` that ports the parts of `BeyondRepWatchCore` the Wear OS watch needs for the link and for recording, and passes every shared contract fixture and golden case; plus the app ID change, an Android SQLite adapter, CI and the ADR. No UI change.

**Architecture:** `apps/wear_os/core` is a Kotlin/JVM library with no Android dependency (JSON via `kotlinx.serialization.json` `JsonElement` only, no serialization plugin; storage behind a small `SqlDatabase` interface). Tests run on the JVM against `contracts/**` read from disk, with an in-process SQLite (xerial `sqlite-jdbc`) implementing `SqlDatabase`. `apps/wear_os/app` gets an `AndroidSqlDatabase` adapter over `android.database.sqlite` and the new `applicationId`. Each Kotlin file ports the Swift file of the same name; the Swift tests are the behavioural spec and are ported first.

**Tech Stack:** Kotlin 2.1.20 (JVM 17), Gradle 8.11.1 wrapper, AGP 8.9.2, kotlinx-serialization-json 1.8.1, JUnit 5 (`kotlin("test")` + `junit-jupiter`), `org.xerial:sqlite-jdbc` 3.49.1.0 (test only).

**Spec:** `docs/superpowers/specs/2026-11-27-wear-os-companion-design.md` (stage 1 in 4.2, structure in 5.1). Reference implementation: `apps/watch_os/Packages/BeyondRepWatchCore/` (Sources and Tests).

## Global Constraints

- Watch `applicationId` = `in.beyondrep.app` (same as the phone, required by the Data Layer). `namespace` stays `in.beyondrep.wear`. `minSdk 30`. `standalone=false` stays.
- `:core` has no `android.*` / `androidx.*` import. Package root `in.beyondrep.wear.core` (subpackages `contracts`, `session`, `link`, `store`).
- Wire output must equal the golden `expected` JSON exactly (compare parsed JSON trees, not strings, unless the Swift test compares strings).
- Unknown keys are rejected at every level; `schema_version` other than 1 is rejected (watch_link) and `envelope_version` rules follow `contracts/workout_sync/v2/README.md`.
- Missing health values stay missing, never 0. No health value is logged.
- Time: `java.time.Instant` and an injected `clock: () -> Instant`; time zones via `java.time.ZoneId`.
- Behaviour must match the Swift source line for line in meaning. Where Swift and the contract README disagree, stop and report; do not pick one.
- New dependencies are only those listed in Tech Stack (approved with the design). No Health Services, Data Layer or Compose changes in this stage.
- Public repo: synthetic data only; never commit keys or `local.properties`.
- Out of scope this stage (do not port): `Glance/*` (stage 2), `FollowerSession` (stage 4), `WatchHealth`, `WatchHealthDerivation`, `HeldWatchHealth` (not used on Wear, see spec stage 5), the `workout_link`-sending path of the journal (`queueWorkoutLink`, `pendingLinks`, `queuedLinkAccountKey`, `links` table). The `WatchMessage` codec still decodes and encodes every message type, including `workout_link`.

## Review Focus

1. A crash between writing an event and its outbox row must leave neither (one transaction per action) — Task 5 test `recordRollsBackWhenOutboxInsertFails`.
2. JSON number edge cases (`10.0`, `10.5`, `1e1`, `-0`, values above `Int.MAX_VALUE`) must be accepted or rejected exactly as `StrictJSON.swift` does; `kotlinx` happily turns `10.0` into an Int otherwise — Task 2 test `numberEdgeCasesMatchSwift`.
3. `original_offset_minutes` across a DST change (`America/New_York` session starting 2026-03-08T06:30:00Z) — Task 4 test `offsetUsesZoneAtStartInstant`.
4. A duplicate or unknown `ack` (already acked, never sent, other account) must not throw or delete anything else — Task 5 test `applyAckIgnoresUnknownAndRepeated`.
5. Timestamps with and without fractional seconds and with `+05:30` offsets parse to the same instant as Swift `WatchTimestamp` — Task 2 test `timestampVariantsMatchSwift`.

---

### Task 1: Module skeleton, app ID, CI, docs

**Files:**
- Create: `apps/wear_os/core/build.gradle.kts`, `apps/wear_os/core/src/main/kotlin/in/beyondrep/wear/core/Contracts.kt` (only `object ContractPaths` for now), `apps/wear_os/core/src/test/kotlin/in/beyondrep/wear/core/FixtureLoader.kt`, `.../core/SmokeTest.kt`
- Modify: `apps/wear_os/settings.gradle.kts`, `apps/wear_os/build.gradle.kts`, `apps/wear_os/app/build.gradle.kts`, `apps/wear_os/app/src/main/AndroidManifest.xml` (nothing but what the ID change needs), `.github/workflows/mobile_ci.yml` (`wear_os` job and its path filter), `apps/wear_os/README.md`, `.gitignore` only if `apps/wear_os/local.properties` / `core/build` are not already ignored.
- Add: this plan and the spec are already in the branch; commit them in this task.

**Interfaces:**
- Produces: `FixtureLoader.repoRoot(): java.nio.file.Path` (walks up from `user.dir` until a `contracts` directory exists), `FixtureLoader.text(relative: String): String`, `FixtureLoader.files(relativeDir: String): List<Path>` (`.json` only, sorted by file name) — mirrors `FixtureLoader.swift`.

- [ ] **Step 1:** Write `SmokeTest.loadsAContractFixture`: `FixtureLoader.files("contracts/watch_link/v1/fixtures/valid")` is not empty and every file parses with `Json.parseToJsonElement`.
- [ ] **Step 2:** Run `cd apps/wear_os && ./gradlew :core:test -Pbeyondrep.coreOnly=true` → FAIL (no `:core` project).
- [ ] **Step 3:** Add `:core` (`kotlin("jvm") version "2.1.20"` declared `apply false` in the root build, `jvmToolchain(17)` or `kotlin { jvmToolchain(17) }`, `tasks.test { useJUnitPlatform() }`). In `settings.gradle.kts`: always `include(":core")`; `include(":app")` unless Gradle property `beyondrep.coreOnly` is `"true"` (lets the JVM tests run on machines without an Android SDK). App: `applicationId = "in.beyondrep.app"`, `implementation(project(":core"))`.
- [ ] **Step 4:** Run the command again → PASS.
- [ ] **Step 5:** CI: in the `wear_os` job run `./gradlew :core:test :app:assembleDebug --no-daemon`; add `contracts/**` to the `wear_os` path filter so contract changes rerun Kotlin. Run `python3 -m unittest discover -s tool -p 'test_*.py'` from the repo root → PASS (layout and Codemagic tests).
- [ ] **Step 6:** README: describe `core/` and `app/`, the `-Pbeyondrep.coreOnly=true` switch, and that the app ID is now the phone's. Commit (`feat(wear): add the Kotlin watch core module and use the phone app id`).

### Task 2: Contract codecs

**Files:**
- Create in `core/src/main/kotlin/in/beyondrep/wear/core/contracts/`: `StrictJson.kt`, `WatchTimestamp.kt`, `WorkoutEventV2.kt`, `WatchMessage.kt`
- Test: `core/src/test/kotlin/in/beyondrep/wear/core/contracts/ContractFixtureTest.kt`, `WatchTimestampTest.kt`, `StrictJsonTest.kt`

**Interfaces:**
- Produces: `class ContractException(val code: String) : Exception(code)`; `object WatchTimestamp { fun milliseconds(text: String): Long?; fun instant(text: String): Instant? }`; `data class EventHeader`, `data class SetValues`, `data class WorkoutStartedPayload`, `data class ExerciseAddedPayload`, `sealed interface WorkoutEventV2 { companion object { fun decode(json: String): WorkoutEventV2 } fun encode(): String }`; `data class SessionCommand`; `sealed interface WatchMessageBody` (one subclass per `type` in `message.schema.json`); `data class WatchMessage(messageId, sentAtUtc, accountKey, body) { companion object { fun decode(json: String): WatchMessage } fun encode(): String }`. Field names: Swift's, in camelCase.

- [ ] **Step 1:** Port `ContractFixtureTests.swift` and `WatchTimestampTests.swift` to Kotlin. Required at minimum: every file in `contracts/watch_link/v1/fixtures/valid` decodes and re-encodes to an equal JSON tree; every file in `.../fixtures/invalid` throws `ContractException`; the same for `contracts/workout_sync/v2/fixtures/{valid,invalid}` with `WorkoutEventV2`.
- [ ] **Step 2:** Add `StrictJsonTest.numberEdgeCasesMatchSwift`: for an integer field (`reps` in a `set_logged` payload) `10` accepted; `10.5`, `"10"`, `true` rejected; `10.0` and `1e1` give the result `StrictJSON.swift` gives (read it, write the expectation, comment the Swift line it mirrors); a value above `Int.MAX_VALUE` rejected. Add `WatchTimestampTest.timestampVariantsMatchSwift`: `2026-11-27T10:00:00Z`, `2026-11-27T10:00:00.250Z`, `2026-11-27T15:30:00+05:30` → millis equal to Swift's for the same strings (`1795773600000`, `1795773600250`, `1795773600000`); garbage → null.
- [ ] **Step 3:** Run `./gradlew :core:test -Pbeyondrep.coreOnly=true --tests '*contracts*'` → FAIL.
- [ ] **Step 4:** Port the four Swift files. Parse with `Json.parseToJsonElement`, then walk `JsonObject`s with an explicit allowed-key set per object, as `StrictJSON.swift` does; encode by building `JsonObject`s with the same key omission rules as Swift (optional keys left out, never `null`, unless Swift writes `null`).
- [ ] **Step 5:** Run → PASS. Commit (`feat(wear-core): watch_link v1 and workout_sync v2 codecs`).

### Task 3: Replay, template, cursor, set input, rest clock

**Files:**
- Create in `core/.../session/`: `WorkoutReplay.kt`, `WorkoutTemplate.kt`, `WorkoutCursor.kt`, `SetInput.kt`, `RestClock.kt`
- Test: `ReplayCaseTest.kt`, `WorkoutTemplateTest.kt`, `WorkoutCursorTest.kt`, `SetInputTest.kt`, `RestClockTest.kt` (ports of the Swift tests of the same names)

**Interfaces:**
- Consumes: Task 2 types.
- Produces: `object WorkoutReplay { fun replay(events: List<WorkoutEventV2>): ReplayResult }` with `ReplayResult` matching the `expected` shape of `cases/replay/*.json`; `data class WorkoutTemplate` with `decode(json)`/`encode()`; `WorkoutCursor`, `SetInput`, `RestClock` with Swift's members (`RestClock.deadline(events): Instant?`, `RestClock.extendedSeconds(remaining: Duration): Int`, `SetInput.step/range/clamp/grams/displayWeight/value/applying`).

- [ ] **Step 1:** `ReplayCaseTest`: for every `contracts/watch_link/v1/cases/replay/*.json`, `WorkoutReplay.replay(events)` serialised equals `expected` (dynamic tests, one per file name). Port the other four Swift test files.
- [ ] **Step 2:** Run `--tests '*session*'` → FAIL.
- [ ] **Step 3:** Port the five Swift files.
- [ ] **Step 4:** Run → PASS. Commit (`feat(wear-core): workout replay, template, cursor, set input and rest clock`).

### Task 4: Session state and completed workout builders

**Files:**
- Create: `core/.../link/SessionStateBuilder.kt`, `core/.../session/CompletedWorkoutBuilder.kt`
- Test: `SessionStateBuilderTest.kt`, `CompletedWorkoutBuilderTest.kt`

**Interfaces:**
- Consumes: Tasks 2–3.
- Produces: `object SessionStateBuilder { data class Rejection(val commandId: String, val reason: String); fun message(...): WatchMessage }` and `object CompletedWorkoutBuilder { fun message(...): WatchMessage }` with Swift's parameters (`healthkitWorkoutUuid: String?` kept; Wear passes null).

- [ ] **Step 1:** Golden tests over `cases/session_state/*.json` and `cases/completed/*.json`: build from `events` + `context`, compare to `expected` as JSON trees. Port the remaining assertions of the two Swift test files.
- [ ] **Step 2:** Add `CompletedWorkoutBuilderTest.offsetUsesZoneAtStartInstant`: a session with `time_zone` `America/New_York` started at `2026-03-08T06:30:00Z` (EST, before the 07:00Z switch) and completed at `2026-03-08T08:00:00Z` → `original_offset_minutes` = `-300`; the same started at `2026-03-08T07:30:00Z` → `-240`.
- [ ] **Step 3:** Add `CompletedWorkoutBuilderTest.omitsHealthkitUuidWhenNull`: building with `healthkitWorkoutUuid = null` gives a body with no `healthkit_workout_uuid` key, and the message decodes with `WatchMessage.decode`.
- [ ] **Step 4:** Run `--tests '*Builder*'` → FAIL. Port the two Swift files. Run → PASS. Commit (`feat(wear-core): session state and completed workout builders`).

### Task 5: SQL adapter and journal

**Files:**
- Create: `core/.../store/SqlDatabase.kt`, `core/.../store/WatchJournal.kt`
- Test: `core/src/test/.../store/JdbcSqlDatabase.kt` (test helper), `WatchJournalTest.kt`

**Interfaces:**
- Produces:
  ```kotlin
  sealed interface SqlValue { data class Text(val v: String); data class Int64(val v: Long); data object Null }
  interface SqlDatabase {
      fun execute(sql: String, args: List<SqlValue> = emptyList())
      fun query(sql: String, args: List<SqlValue> = emptyList()): List<List<SqlValue>>
      fun <T> transaction(block: () -> T): T   // nested calls join the outer one, like SQLiteDatabase.swift `depth`
  }
  class WatchJournal(db: SqlDatabase, clock: () -> Instant = Instant::now)
  ```
  `WatchJournal` public methods: the Swift ones listed in `WatchJournal.swift` except the excluded link methods (Global Constraints), same names in camelCase, `UUID`→`String` where Swift takes `UUID`, tuples → small data classes (`BindingState`, `CommandLogEntry`, `WaitingCounts`, `AckEffect`).

- [ ] **Step 1:** Port `WatchJournalTests.swift` except tests that exercise upgrades from older Swift schema versions (Wear has no old databases) and the excluded link methods; list the skipped Swift test names in a comment at the top of `WatchJournalTest.kt`. Each test opens a fresh `JdbcSqlDatabase` on a temp file.
- [ ] **Step 2:** Add `recordRollsBackWhenOutboxInsertFails`: wrap `JdbcSqlDatabase` so the `INSERT INTO outbox` statement throws; `journal.record(...)` throws and afterwards `events(sessionId)` is empty and `pendingOutbox(10)` is empty.
- [ ] **Step 3:** Add `applyAckIgnoresUnknownAndRepeated`: queue a completed workout, `applyAck(id, "accepted")` returns an effect; a second call with the same id and a call with an unknown id return null, do not throw, and leave another queued message in `pendingCompleted`.
- [ ] **Step 4:** Run `--tests '*store*'` → FAIL.
- [ ] **Step 5:** Implement. Schema: create Swift's **final** tables (journal v8 minus `links`) directly in one versioned migration (`PRAGMA user_version = 1`), with `PRAGMA journal_mode=WAL` and `foreign_keys` as Swift sets them. SQL text copied from Swift wherever possible.
- [ ] **Step 6:** Run → PASS. Commit (`feat(wear-core): SQLite journal`).

### Task 6: Session machine, controller, command applier

**Files:**
- Create: `core/.../session/SessionMachine.kt`, `WorkoutController.kt`, `OrphanSessionPolicy.kt`, `core/.../link/CommandApplier.kt`
- Test: ports of `SessionMachineTests.swift`, `WorkoutControllerTests.swift`, `OrphanSessionPolicyTests.swift`, `CommandApplierTests.swift`

**Interfaces:**
- Consumes: Tasks 2–5.
- Produces: `SessionMachine`, `class WorkoutController` (`start`, `restore` companion functions; `log`, `setRpe`, `skip`, `extendRest`, `skipRest`, `pause`, `resume`, `addSet`, `addExercise`, `focus`, `markCompleted`, `queueCompleted(healthkitWorkoutUuid: String?)`, `apply(message)`, `sessionState(...)`, `discard`), `enum class RejectReason`, `sealed interface CommandOutcome`, `object CommandApplier { fun apply(message: WatchMessage, controller: WorkoutController): CommandOutcome }`, `object OrphanSessionPolicy { fun shouldDiscard(restoredSession: Boolean, unresolvedPendingFinish: Boolean): Boolean }`.

- [ ] **Step 1:** Port the four Swift test files. Run `--tests '*Session*' --tests '*Controller*' --tests '*CommandApplier*' --tests '*Orphan*'` → FAIL.
- [ ] **Step 2:** Port the four Swift files. Every controller action that changes state goes through one `journal` transaction, as in Swift `commit`.
- [ ] **Step 3:** Run → PASS. Commit (`feat(wear-core): session machine, workout controller and command applier`).

### Task 7: Phone inbox and ack builder

**Files:**
- Create: `core/.../link/PhoneInbox.kt`, `core/.../link/AckBuilder.kt`
- Test: ports of `PhoneInboxTests.swift`, `AckBuilderTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 5.
- Produces: `data class AckOutcome(messageId, accountKey, result, reason: String?)`; `object AckBuilder { fun json(outcome: AckOutcome, messageId: String, now: Instant): String }`; `class PhoneInbox(journal: WatchJournal) { fun receiveContext(latestByType: Map<String, String>, now: Instant): List<AckOutcome>; fun receiveQueued(json: String, now: Instant): List<AckOutcome> }`. These replace Swift's `receive(applicationContext:)` / `receive(userInfo:)`: on Wear the context is one Data Layer item per message type holding the message JSON (spec 5.2), and each queued item holds one message JSON. Port the Swift dictionary unwrapping into these two shapes; everything after decoding is Swift's logic unchanged.

- [ ] **Step 1:** Port the Swift tests, rewriting only the input construction to the two new shapes. Run `--tests '*Inbox*' --tests '*Ack*'` → FAIL.
- [ ] **Step 2:** Implement. Run → PASS. Commit (`feat(wear-core): phone inbox and ack builder`).

### Task 8: Android SQLite adapter, ADR and docs

**Files:**
- Create: `apps/wear_os/app/src/main/java/in/beyondrep/wear/store/AndroidSqlDatabase.kt`, `docs/adr/0015-wear-os-companion.md`
- Modify: `apps/wear_os/AGENTS.md` (core/app split; journal rule), `docs/ROADMAP.md` ("Later phase — Wear OS companion": stage list from the spec, stage 1 implemented in source), `CLAUDE.md` "Project state" (one bullet: Wear OS stage 1, core only, not released or device-verified), `docs/WEARABLES.md` (one short paragraph pointing at the ADR), `contracts/watch_link/v1/README.md` (one line: Kotlin core in `apps/wear_os/core` runs the same fixtures and cases).

**Interfaces:**
- Consumes: `SqlDatabase` (Task 5).
- Produces: `class AndroidSqlDatabase(context: Context, name: String = "beyondrep_watch.db") : SqlDatabase` using `SQLiteDatabase`/`SQLiteOpenHelper`, `beginTransaction`/`setTransactionSuccessful`/`endTransaction` with the same nesting rule; not used by any screen yet.

- [ ] **Step 1:** Implement the adapter (no unit test: it is verified by `:app:assembleDebug` on CI and used in stage 2; say so in the PR).
- [ ] **Step 2:** ADR-0015, status **Accepted — approved by the project owner on 2026-11-27** (Adi approved the design): native Kotlin/Compose Wear OS companion with the same app ID and signing key as the phone; same rules as ADR-0012 decisions 3, 5, 6 and 7; transport is the Wear Data Layer (mapping table from spec 5.2); heart rate and calories of a watch workout reach Health Connect through the phone (spec 4.3, including consent, retention and phone-owned workouts), amending ADR-0012 decision 4 and HEALTH_DATA.md when stage 3 lands; builds on ADR-0014 (phone writes workouts to Health Connect). Consequences: stage list; nothing released or device-verified.
- [ ] **Step 3:** From the repo root run `python3 -m unittest discover -s tool -p 'test_*.py'` and `cd apps/wear_os && ./gradlew :core:test -Pbeyondrep.coreOnly=true` → PASS. If an Android SDK is available, also `./gradlew :core:test :app:assembleDebug`; otherwise record "not run locally, CI only".
- [ ] **Step 4:** Commit (`docs(wear): ADR-0015 and stage 1 docs; Android SQLite adapter`).
