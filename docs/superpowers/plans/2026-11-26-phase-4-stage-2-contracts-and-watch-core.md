# Phase 4 stage 2: message contracts and watch core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every phone↔watch message and the watch's offline storage and session rules in tested code, with no UI and no transport yet, so stages 3–5 only wire things together.

**Architecture:** Two language-neutral contracts under `contracts/` (JSON Schema + synthetic fixtures + replay cases) are the authority. Dart (phone) gets strict codecs for them in a new `lib/features/watch/domain/`. A pure Swift package `apps/watch_os/Packages/BeyondRepWatchCore` gets the same codecs plus the on-watch SQLite journal, the session state machine and event replay, all tested against the same fixture files. ADR-0012 records the policy changes before any code depends on them.

**Tech Stack:** JSON Schema 2020-12 + Python `jsonschema` (existing `tool/` tests), Dart 3 / `crypto` 3.0.7 (already a dependency), Swift 5.9 package with Foundation + system `SQLite3` (no third-party packages), XCTest, GitHub Actions `macos-15`.

**Spec:** `docs/superpowers/specs/2026-11-26-phase-4-watch-and-tablet-design.md` §4.3–4.6, §5.2–5.6.

## Global Constraints

- Fixtures use **synthetic ids and values only** (public repo). No real emails, user ids or health exports.
- `contracts/workout_sync/v1/` stays byte-for-byte unchanged; v2 lives beside it.
- Unknown `schema_version` is rejected, never read as an older version (SYNC_PROTOCOL).
- Health values may appear **only** in `watch_link/v1` `health_snapshot`; the existing "no sensor words in workout events" test must also hold for `workout_sync/v2` valid fixtures.
- The watch never holds the raw Supabase user id or email: only the 64-hex `account_key`.
- Cloud workout payload is unchanged except `origin` may be `"beyondrep_watch"`; field rules exactly as `docs/SYNC_PROTOCOL.md` "Cloud workout payload" (at most 120 exercises, 300 sets each, set `kind` working|warmup, `status` planned|completed|skipped, `input_unit` kg|lb, optional `reps`, `duration_seconds`, `load_grams`, `rpe`, `completed_at_utc`; a completed set needs `completed_at_utc` and `reps` or `duration_seconds`; muscle array rules as written there).
- Swift: Foundation and `SQLite3` only; package platforms `.watchOS(.v10), .macOS(.v14)`; swift-tools-version 5.9.
- Swift cannot be built in the Linux container. Swift tasks are verified by pushing the branch and reading the GitHub Actions run of `watchos_smoke.yml` (Task 7 adds the `swift test` step first so later Swift tasks have a gate). Dart and Python run locally.
- Workflow edits keep every action pinned to a full commit SHA (`tool/test_workflow_action_pins.py`).
- No Supabase migration in this stage (it lands with stage 4, where the uploader starts sending `beyondrep_watch`).

## Review Focus

1. **Duplicate delivery** of the same event (same `event_id`) or completed workout: replay and journal must be idempotent. Replay case + journal test in Tasks 8/9.
2. **Out-of-order or gapped `sequence`** from one device: replay applies in sequence order and reports the gap rather than inventing data. Replay case in Task 8.
3. **Correction of a correction** (A logged, B supersedes A, C supersedes B): final value is C, history keeps A, B, C. Replay case in Task 8.
4. **Crash between the state write and the outbox write** on the watch: both or neither exist after reopen. Journal test in Task 9.
5. **Timed sets** (duration, no reps) and **catalogue exercise ids** that are not UUIDs (`builtin.v1.synthetic-move-1`): valid in v2. Fixtures in Task 2.

---

### Task 1: ADR-0012 and protocol docs

**Files:**
- Create: `docs/adr/0012-apple-watch-companion.md`
- Modify: `docs/SYNC_PROTOCOL.md` (rule 5; add a "Watch link v1" section pointing at `contracts/watch_link/v1`), `docs/adr/0005-mandatory-auth-and-workout-sync.md` (one "Amended by ADR-0012" line at the top, nothing else), `docs/HEALTH_DATA.md` (snapshot exception paragraph), `docs/WEARABLES.md` (status line: Apple Watch companion in progress per ADR-0012; Wear OS deferred)

ADR-0012 decides, in this order: (1) native SwiftUI watch companion embedded in the iPhone app, Wear OS deferred; (2) the watch writes exactly one `HKWorkout` per watch-run session with workout share permission, and records its UUID in a `platform_workout_exported` event; (3) completed watch workouts are backed up once, by the phone, after durable import, with cloud `origin` `"beyondrep_watch"`; in-progress watch sessions, raw heart rate and the health snapshot are never backed up; (4) the phone computes all health scores; the watch keeps only today's `health_snapshot`, on the watch, cleared at local midnight and on sign out, never synced or logged; (5) accounts on the watch are an HMAC account key; (6) session ownership: the starter owns, the other sends commands, later edit supersedes and the earlier stays in history; (7) trigger to revisit a shared native formula library: the watch must compute a score itself. Status: Accepted 2026-11-26 (owner approved the design).

- [ ] **Step 1:** Write the ADR and doc edits.
- [ ] **Step 2: Run** from repo root `python3 -m unittest discover -s tool -p 'test_*.py'` — PASS (layout/README tests).
- [ ] **Step 3: Commit** `docs: ADR-0012 Apple Watch companion`

---

### Task 2: `workout_sync/v2` schema and fixtures

**Files:**
- Create: `contracts/workout_sync/v2/envelope.schema.json`, `contracts/workout_sync/v2/README.md`, `contracts/workout_sync/v2/fixtures/valid/*.json`, `contracts/workout_sync/v2/fixtures/invalid/*.json`
- Modify: `tool/test_protocol_contract.py` (parameterise over v1 and v2; keep v1 asserts)

v2 envelope = v1 envelope with `schema_version` const `2`, same top-level fields, and these `type`s and payloads (all `additionalProperties: false`):

| type | payload |
|---|---|
| `workout_started` | `activity_type` ("traditional_strength_training"), `name` (1–120), `owner` (watch\|phone), `account_key` (`^[0-9a-f]{64}$`), optional `plan_id` (string 1–128), optional `program_day` {`program_id` string, `local_date` YYYY-MM-DD} |
| `exercise_added` | `exercise_id` (string 1–128), `name` (1–120), `kind` (reps\|duration), `position` (int ≥ 0) |
| `set_logged` | `set_id` uuid, `exercise_id` string 1–128, `position` int ≥ 0, `kind` working\|warmup, `input_unit` kg\|lb, optional `reps` int ≥ 0, `duration_seconds` int ≥ 1, `load_grams` int ≥ 0, `rpe` number 1–10 multipleOf 0.5; **anyOf** requires `reps` or `duration_seconds` |
| `set_corrected` | `set_logged` fields + `supersedes_event_id` uuid |
| `set_skipped` | `set_id` uuid |
| `rest_started` | `seconds` int 1–3600, `deadline_utc` date-time |
| `rest_cleared`, `workout_paused`, `workout_resumed`, `workout_completed`, `workout_abandoned` | empty object |
| `platform_workout_exported` | as v1 |

Valid fixtures (one per type at least, plus `set_logged_timed.json` with `duration_seconds` and no reps, and `set_logged_catalogue_id.json` with `exercise_id` `builtin.v1.synthetic-move-1`). Invalid fixtures: `v1_version.json` (schema_version 1 against v2), `set_without_reps_or_duration.json`, `rpe_out_of_range.json` (10.5), `rpe_not_half_step.json` (7.3), `bad_account_key.json` (63 hex), `extra_set_field.json` (`heart_rate`), `unknown_type.json`.

- [ ] **Step 1: Write the failing test:** in `test_protocol_contract.py` add `ProtocolV2FixturesTest` with `test_valid_messages` (≥ 12 fixtures), `test_invalid_messages` (≥ 7), `test_no_platform_sensor_payload_in_valid_fixtures` (same forbidden words as v1).
- [ ] **Step 2: Run** `python3 -m unittest tool.test_protocol_contract` — FAIL (no v2 dir).
- [ ] **Step 3:** Write the schema, README (what changed from v1 and why) and fixtures.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat(contracts): workout_sync v2 for RPE, timed sets and catalogue ids`

---

### Task 3: `watch_link/v1` schema, fixtures and replay cases

**Files:**
- Create: `contracts/watch_link/v1/message.schema.json`, `README.md`, `fixtures/valid/*.json`, `fixtures/invalid/*.json`, `cases/replay/*.json`
- Create: `tool/test_watch_link_contract.py`

Envelope (all messages): `schema_version` const 1, `message_id` uuid, `type`, `sent_at_utc` date-time, `account_key` `^[0-9a-f]{64}$`, `body` object. `additionalProperties: false` everywhere.

| type | direction | body |
|---|---|---|
| `account_binding` | phone→watch | `unit` kg\|lb |
| `account_cleared` | phone→watch | `wipe_unsent` bool (true only on account deletion) |
| `plans_snapshot` | phone→watch | `generated_at_utc`; `plans` [≤ 100] of {`plan_id`, `name`, `exercises` [≤ 40] of {`exercise_id`, `name`, `kind` reps\|duration, optional `muscle`, `sets` [≤ 30] of {`position`, `kind`, optional `target_reps`, `target_seconds`, `target_load_grams`, `rest_seconds`}}}; optional `today` {`plan_id`, `program_id`, `local_date`, `label`}; `recent_exercises` [≤ 30] of {`exercise_id`, `name`, `kind`} |
| `health_snapshot` | phone→watch | `local_date` YYYY-MM-DD, `as_of_utc`; each optional: `readiness` {`score` 0–100 int, `band` good\|fair\|low, `headline` ≤ 60, `reason` ≤ 140}, `sleep` {optional `score` 0–100, `asleep_minutes`, `deep_minutes`, `rem_minutes`}, `resting_hr_bpm`, `hrv_ms`, `hrv_kind` sdnn\|rmssd, `steps`, `active_energy_kcal` (all non-negative) |
| `workout_event` | either | `event`: a `workout_sync/v2` envelope (`$ref` to `../../workout_sync/v2/envelope.schema.json`) |
| `session_state` | owner→other | `session_id`, `owner`, `status` active\|paused, `name`, `started_at_utc`, `last_sequence`, optional `current_set_id`, optional `rest_deadline_utc`, `exercises` [{`exercise_id`, `name`, `kind`, `sets` [{`set_id`, `position`, `kind`, `status` planned\|completed\|skipped, optional values as `set_logged`}]}] |
| `session_command` | other→owner | `session_id`, `command_id` uuid, `command` log_set\|correct_set\|skip_set\|start_rest\|clear_rest\|pause\|resume\|finish\|discard, optional `set` (the `set_logged` value fields + `set_id`), optional `rest_seconds` |
| `completed_workout` | watch→phone | `workout`: the cloud workout payload with `origin` const `beyondrep_watch` (write the schema from SYNC_PROTOCOL "Cloud workout payload"), `last_sequence`, optional `healthkit_workout_uuid` |
| `ack` | either | `acked_message_id` uuid, `result` stored\|duplicate\|rejected, optional `reason` wrong_account\|invalid\|unsupported_version |

Replay cases (`cases/replay/<name>.json`): `{ "events": [v2 envelopes…], "expected": { "status": "active|paused|completed|abandoned", "sets": [{"set_id", "status", "reps"?, "duration_seconds"?, "load_grams"?, "rpe"?, "history": [event_id…]}], "volume_grams": int, "completed_sets": int, "gaps": [sequence numbers missing] } }`. Write at least: `basic_three_sets`, `timed_set`, `duplicate_event`, `correction_chain` (A→B→C), `out_of_order_sequence` (delivered 1,3,2 → same result as 1,2,3), `gap_in_sequence` (1,2,4 → `gaps: [3]`, set from 4 still applied), `skip_then_log` (skip then a later `set_logged` for the same set: logged wins), `abandoned`. Volume = Σ over completed working **and** warmup sets of `reps × load_grams` (timed sets add 0) — match `apps/mobile/lib/features/progress` volume; if that code excludes warmups, follow it and say so in the README.

- [ ] **Step 1: Write the failing test** `tool/test_watch_link_contract.py`: schema checks itself; ≥ 10 valid and ≥ 8 invalid fixtures (include `missing_account_key`, `bad_local_date`, `readiness_band_unknown`, `completed_workout_wrong_origin` (`northstar_phone`), `negative_steps`, `command_unknown`, `ack_bad_result`, `event_v1_inside`); every replay case's events validate against v2; `health_snapshot` is the only valid fixture containing `sleep`/`hrv`/`steps`.
- [ ] **Step 2: Run** `python3 -m unittest tool.test_watch_link_contract` — FAIL.
- [ ] **Step 3:** Write schema, README, fixtures, cases.
- [ ] **Step 4: Run** — PASS; then the whole `tool` suite — PASS.
- [ ] **Step 5: Commit** `feat(contracts): watch_link v1 messages and replay cases`

---

### Task 4: Dart codecs for both contracts

**Files:**
- Create: `apps/mobile/lib/features/watch/domain/workout_event_v2.dart`, `apps/mobile/lib/features/watch/domain/watch_message.dart`
- Test: `apps/mobile/test/watch/contract_fixtures_test.dart`

**Interfaces:**
- Produces:
  - `sealed class WorkoutEventV2` with one final subclass per v2 type; common fields `eventId`, `workoutId`, `sessionId`, `originDeviceId`, `sequence`, `occurredAtUtc`, `recordedAtUtc`, `timeZone`. `static WorkoutEventV2 fromJson(Map<String, Object?> json)` throws `WatchContractException(String code)`; `Map<String, Object?> toJson()`.
  - `sealed class WatchMessage` with one subclass per watch_link type; envelope fields `messageId`, `sentAtUtc`, `accountKey`. `static WatchMessage fromJson(Map<String, Object?>)`, `toJson()`.
  - `class WatchContractException implements Exception { final String code; }` — codes `unsupported_version`, `unknown_type`, `unknown_key`, `missing_field`, `invalid_value`.
  - Strictness equals the schemas: unknown keys rejected at every level, ranges and patterns checked. `completed_workout.workout` is kept as `Map<String, Object?>` and checked for `origin == 'beyondrep_watch'` here; full payload validation reuses the existing cloud workout validator in stage 4. **Stage-4 requirement:** the phone import must run that cloud-payload validator (including the reps-or-duration rule) on `completed_workout.workout` before anything enters the outbox; neither stage-2 codec validates it beyond `origin` and a string `workout_id`.

- [ ] **Step 1: Write the failing test:** load every file under `../../contracts/workout_sync/v2/fixtures` and `../../contracts/watch_link/v1/fixtures` (path relative to `apps/mobile`); valid ones `fromJson` then `toJson` round-trip to the same JSON (deep equality); invalid ones throw `WatchContractException`. Also `rejects v1 envelope with unsupported_version`.
- [ ] **Step 2: Run** `flutter test test/watch/contract_fixtures_test.dart` — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — PASS; `flutter analyze` clean.
- [ ] **Step 5: Commit** `feat(watch): Dart codecs for watch contracts`

---

### Task 5: Account key

**Files:**
- Create: `apps/mobile/lib/features/watch/domain/watch_account_key.dart`
- Test: `apps/mobile/test/watch/watch_account_key_test.dart`

**Interfaces:**
- Produces: `String watchAccountKey(String userId)` — lowercase hex of HMAC-SHA-256(key: utf8 `'beyondrep.watch.account.v1'`, message: utf8 `userId`).

- [ ] **Step 1: Write the failing tests:** `same user gives the same 64-hex key`; `different users give different keys`; `key does not contain the user id`; `known vector`: compute the expected hex for user id `00000000-0000-4000-8000-000000000001` once with `python3 -c "import hmac,hashlib;print(hmac.new(b'beyondrep.watch.account.v1',b'00000000-0000-4000-8000-000000000001',hashlib.sha256).hexdigest())"` and paste it into the test.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** with `package:crypto`. **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat(watch): account key for the watch`

---

### Task 6: Swift package skeleton and CI gate

**Files:**
- Create: `apps/watch_os/Packages/BeyondRepWatchCore/Package.swift`, `Sources/BeyondRepWatchCore/BeyondRepWatchCore.swift` (namespace + version constants), `Tests/BeyondRepWatchCoreTests/FixtureLoader.swift`, `Tests/BeyondRepWatchCoreTests/SmokeTests.swift`
- Modify: `.github/workflows/watchos_smoke.yml` (path filter adds `contracts/**`; the macOS job gets a step `swift test --package-path apps/watch_os/Packages/BeyondRepWatchCore` before the Xcode build), `apps/watch_os/README.md` (package section)

`FixtureLoader` finds the repo root by walking up from `#filePath` until it sees `contracts/`, and exposes `func json(_ relativePath: String) throws -> Data` and `func files(in relativeDir: String) throws -> [URL]`.

- [ ] **Step 1: Write** `SmokeTests.testFindsContracts` asserting `files(in: "contracts/watch_link/v1/fixtures/valid")` is non-empty.
- [ ] **Step 2: Push** the branch and read the `WatchOS standalone build proof` run (GitHub MCP `actions_list` / `get_job_logs`). Expect the new step to run and PASS. If the package fails to build, fix and push again (re-read only that job).
- [ ] **Step 3: Run** `python3 -m unittest tool.test_workflow_action_pins` — PASS.
- [ ] **Step 4: Commit** `build(watch): BeyondRepWatchCore package and swift test in CI`

---

### Task 7: Swift codecs

**Files:**
- Create: `Sources/BeyondRepWatchCore/Contracts/WorkoutEventV2.swift`, `Contracts/WatchMessage.swift`, `Contracts/StrictJSON.swift`
- Test: `Tests/BeyondRepWatchCoreTests/ContractFixtureTests.swift`

**Interfaces:**
- Produces: `enum WorkoutEventV2` (case per type with associated payload structs) with `init(json: Data) throws` and `func jsonData() throws -> Data`; `enum WatchMessage` likewise; `struct ContractError: Error { let code: String }` with the same codes as Dart. `StrictJSON` decodes via `JSONSerialization` into `[String: Any]` and checks allowed keys per object (Codable alone ignores unknown keys, which the schema forbids).

- [ ] **Step 1: Write the failing test:** for every valid fixture in both contracts decode, encode, and compare as `NSDictionary` equality with the original; every invalid fixture throws `ContractError`.
- [ ] **Step 2: Push**, read CI — FAIL in `ContractFixtureTests`.
- [ ] **Step 3: Implement.** **Step 4: Push**, read CI — PASS.
- [ ] **Step 5: Commit** `feat(watch-core): strict codecs for watch contracts`

---

### Task 8: Event replay and session state machine

**Files:**
- Create: `Sources/BeyondRepWatchCore/Session/WorkoutReplay.swift`, `Session/SessionMachine.swift`
- Test: `Tests/BeyondRepWatchCoreTests/ReplayCaseTests.swift`, `SessionMachineTests.swift`

**Interfaces:**
- Produces:
  - `struct ReplayedWorkout: Equatable { status; sets: [ReplayedSet]; volumeGrams: Int; completedSets: Int; gaps: [Int] }`, `func replay(_ events: [WorkoutEventV2]) -> ReplayedWorkout` — dedupe by `event_id`, sort by `sequence`, record missing sequence numbers in `gaps`, apply corrections by `supersedes_event_id` keeping every event id in that set's `history`.
  - `struct SessionMachine` — `init(sessionId:, owner:, accountKey:, deviceId:, clock: () -> Date, timeZone: String)`; methods `start(name:planId:programDay:exercises:) -> WorkoutEventV2`, `log(set:) -> WorkoutEventV2`, `correct(setId:values:) -> WorkoutEventV2`, `skip(setId:)`, `startRest(seconds:)`, `clearRest()`, `pause()`, `resume()`, `complete()`, `abandon()`, each returning the next event with `sequence` = previous + 1, and throwing `SessionError.invalidTransition` (e.g. `log` while paused, anything after complete/abandon). `apply(command: SessionCommand) throws -> WorkoutEventV2` maps watch_link commands to the same methods. `var state: ReplayedWorkout` equals `replay(allEventsSoFar)`.
- [ ] **Step 1: Write the failing tests:** `ReplayCaseTests` loads every `contracts/watch_link/v1/cases/replay/*.json` and asserts `replay(events) == expected`. `SessionMachineTests`: `sequence increases by one per event`, `log while paused throws`, `nothing after complete`, `correct emits set_corrected superseding the last event for that set`, `state matches replay of emitted events` (property-style over a fixed 20-step script), `command finish maps to complete`.
- [ ] **Step 2: Push**, CI — FAIL. **Step 3: Implement.** **Step 4: Push**, CI — PASS.
- [ ] **Step 5: Commit** `feat(watch-core): event replay and session state machine`

---

### Task 9: On-watch journal (SQLite)

**Files:**
- Create: `Sources/BeyondRepWatchCore/Store/SQLiteDatabase.swift` (thin wrapper: open, WAL, `transaction { }`, prepared statements), `Store/WatchJournal.swift`
- Test: `Tests/BeyondRepWatchCoreTests/WatchJournalTests.swift`

**Interfaces:**
- Produces: `final class WatchJournal` — `init(url: URL) throws` (creates tables, `PRAGMA journal_mode=WAL`, `user_version` 1); `func record(_ event: WorkoutEventV2, sessionState: ReplayedWorkout) throws` (one transaction: event row + outbox row + session state); `func pendingOutbox(limit: Int) throws -> [WatchMessage]`; `func acknowledge(messageId: UUID) throws` (removes outbox row; duplicate ack is a no-op); `func saveCompleted(_ msg: WatchMessage) throws`; `func savePlans(_:)`, `func plans()`, `func saveHealth(_:)`, `func health(forLocalDate: String)` (returns nil for any other date), `func clearAccount(_ key: String, wipeUnsent: Bool) throws` (drops plans and health; with `wipeUnsent` also that key's sessions/outbox); `func activeSession() throws -> (events: [WorkoutEventV2], state: ReplayedWorkout)?`.
- Tables (my call; builder may rename): `events(event_id PK, session_id, sequence, json)`, `outbox(message_id PK, account_key, json, created_at)`, `sessions(session_id PK, account_key, status, state_json)`, `plans(account_key PK, json)`, `health(account_key PK, local_date, json)`.

- [ ] **Step 1: Write the failing tests:** `record is atomic` (inject a failure after the event insert via a test hook `failAfterEventInsert`; reopen; neither event nor outbox row exists); `reopen restores the active session and its replayed state`; `duplicate event id is ignored`; `acknowledge removes only that message and is idempotent`; `health for another date is nil`; `clearAccount without wipe keeps unsent outbox`; `clearAccount with wipe removes it`; `outbox survives reopen`.
- [ ] **Step 2: Push**, CI — FAIL. **Step 3: Implement.** **Step 4: Push**, CI — PASS.
- [ ] **Step 5: Commit** `feat(watch-core): durable SQLite journal and outbox`

---

### Task 10: Gate and status docs

- [ ] **Step 1: Run** locally from `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`; from repo root `python3 -m unittest discover -s tool -p 'test_*.py'`. All PASS.
- [ ] **Step 2:** Read the latest `watchos_smoke.yml` run on the branch: package tests and the Xcode build both PASS.
- [ ] **Step 3: Update** `docs/ROADMAP.md` Phase 4 entry and `CLAUDE.md` Project state with one line each: stage 2 (contracts, Dart codecs, watch core) implemented in source, no UI, not device-verified.
- [ ] **Step 4: Commit** `docs: Phase 4 stage 2 status`
