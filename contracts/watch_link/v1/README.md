# BeyondRep watch link v1

**Source of truth:** [message.schema.json](message.schema.json). Phone to Apple Watch and watch to phone messages. Workout events travel inside `workout_event` using [workout_sync/v2](../../workout_sync/v2/README.md). Design and policy: [ADR-0012](../../../docs/adr/0012-apple-watch-companion.md), [SYNC_PROTOCOL.md](../../../docs/SYNC_PROTOCOL.md).

Every message has `schema_version` 1 (other versions are rejected, never read as v1), `message_id`, `type`, `sent_at_utc`, the 64-hex `account_key` (an HMAC of the user id; the raw id and email never reach the watch) and a `body`. Unknown keys are rejected at every level.

`health_snapshot` and `workout_health` are the only messages that may carry health values; the CI test checks that no other valid fixture mentions them. `completed_workout.workout` is the cloud workout payload with `origin` `beyondrep_watch`; its field rules follow `docs/SYNC_PROTOCOL.md` "Cloud workout payload". The codecs (Dart, Swift) check only `origin` and a string `workout_id` of that object. **The stage-4 phone import must run the existing cloud-payload validator, including the reps-or-duration rule, before anything enters the outbox.** A delivered message is not an acknowledgment: durability is the explicit `ack`.

`completed_workout.healthkit_workout_uuid` is the receipt the phone stores to hide the watch's own HealthKit workout from outside workouts. `completed_workout.program_day` (optional, `plan_id`, `program_id`, `local_date`; the watch copies it from `plans_snapshot.today`) tells the phone which program day the workout fulfils: the phone records it only when that plan exists locally and belongs to that program, and imports the workout without it otherwise.

Fixtures are fictional and synthetic. `$id` values use the reserved `.invalid` domain only so the schema can reference the v2 schema; nothing is hosted there.

## Health snapshot extras (optional)

`health_snapshot` carries these optional fields, all additive (`schema_version` stays 1). Missing values are left out, never sent as 0. Fixtures: `valid/health_snapshot_full.json` and the `invalid/health_snapshot_*` files.

- `sleep.core_minutes`, `sleep.awake_minutes`: only when the night has stages.
- `resting_hr_usual_bpm`, `hrv_usual_ms`: the readiness baseline mean, only when a baseline exists.
- `readiness.factors`: 0 to 4 items `{input, status, tone}`. `input` is `sleep`, `hrv`, `resting_hr` or `training_load` and appears at most once; `status` is 1 to 24 code points written by the phone; `tone` is `good`, `neutral` or `caution`.
- `week`: 1 to 7 items, the local days ending on `local_date`, strictly ascending and none later than `local_date`. Each item has `local_date` and optional integer `asleep_minutes`, `sleep_score` (0 to 100), `resting_hr_bpm`, `hrv_ms`, `steps`.

JSON Schema cannot express the duplicate-factor and week-order rules, so the Python test (`cross_field_errors`), Dart and Swift check them in code.

**Old watch builds:** the watch decoder rejects unknown keys, so a watch still on a build from before these fields rejects the new snapshot and shows "—" until it updates. The phone and the watch ship in the same TestFlight build, which is acceptable for an internal build.

## Workout heart rate and calories (Wear OS stage 3b)

`workout_health` (watch to phone) carries the heart rate and total calories of one finished watch workout so the Android phone can write them to Health Connect (ADR-0015). Additive, `schema_version` stays 1. The watch sends it only after the phone acked the `completed_workout`. Fixtures: `valid/workout_health.json`, `valid/workout_health_minimal.json`, `invalid/workout_health_*`.

- Body: `workout_id`, `start_utc`, `end_utc` (end after start), `heart_rate` (0 to 600 items `{at_utc, bpm}`, `bpm` an integer 25 to 250, `at_utc` inside start..end and strictly increasing) and optional `total_kcal` (above 0, at most 10000). Missing values are left out, never 0.
- The watch reduces heart rate to one average per started minute of the workout (`at_utc` = the minute's start, `bpm` rounded half up); a minute without a valid sample is left out.
- JSON Schema cannot express the end-after-start, samples-inside and strictly-increasing rules; the Python test (`workout_health_errors`), Kotlin and Dart check them in code.
- `ack` gains reason `not_written`, allowed only with `rejected`: the phone will not write it (the save-workouts switch is off, the workout was deleted, Health Connect is missing or unsupported, or the phone is not Android). The watch deletes the series on any ack. A write failure, or a missing heart rate or calories permission while the switch is on, sends no ack, so the watch keeps the series (up to 7 days) and resends.

## Live session (stage 5a)

`session_state` and `session_command` carry a workout that runs on the watch to the phone and back. The watch owns the workout; the phone only sends commands. Neither message carries health values.

- `session_state.status` is `active`, `paused` or `ended`. `end_reason` (`completed` or `discarded`) is required with `ended` and not allowed otherwise. `paused_at_utc` is allowed only while paused and `paused_seconds` is the total of earlier pauses, so a phone can show elapsed time as now minus `started_at_utc` minus `paused_seconds` (minus the running pause).
- `applied_command_ids` (at most 20, newest last) lists commands the watch applied; a phone keeps a command pending until its id is there. `rejected_commands` (at most 20) gives a reason: `unknown_session`, `unknown_set`, `invalid_values` or `not_allowed`.
- `session_command.command` adds `add_set` (needs `exercise_id`, allowed for no other command). `log_set`, `correct_set` and `skip_set` require `set`. The watch applies a `command_id` at most once; resending it is not an error.
- Planned sets in `session_state` carry the template's targets (`reps`, `duration_seconds`, `load_grams`, `input_unit`) so a phone can prefill them, and the planned `rest_seconds` (1 to 3600) when the template has one; `status` says whether a set is logged.
- Golden cases for the watch's state builder are in `cases/session_state/`: `events` and `context` (`template`, `unit`, `account_key`, `message_id`, `sent_at_utc`, `applied_command_ids`, `rejected_commands`) in, the full `session_state` message as `expected`.

## Phone-owned workout (stage 5b)

A workout started on the phone is owned by the phone: `session_state.owner` is `phone`, built from the phone's ObjectBox workout, and the watch follows it. The watch sends `session_command` messages (same commands as 5a) and the phone echoes `applied_command_ids` and `rejected_commands`. Two watch-to-phone types are new, neither carries health values:

- `join` (optional `session_id`): a follower is attached; the phone sends its state at once (the watch just launched does not know the session yet and omits it). For a session that is no longer active the phone answers with an `ended` state built from the stored workout, so a watch that missed the end still finishes or discards. Fixtures: `valid/join.json`, `valid/join_any.json`.
- `workout_link` (`workout_id`, `healthkit_workout_uuid`): the watch saved the one `HKWorkout` for that phone workout. The phone stores the receipt in one transaction and acks it; a link for an unknown or unfinished workout gets no ack, so the watch resends it. Fixtures: `valid/workout_link.json`, `valid/join.json`, `valid/session_state_phone.json`.

## Session state cases

`cases/session_state/<name>.json` holds the golden input and output of the watch's state builder (`SessionStateBuilder.swift`): `description`, `events` (workout_sync v2 envelopes), `context` and `expected` (the full `session_state` message). Swift builds the message from `events` and `context` and must equal `expected`; `tool/test_watch_link_contract.py` has an independent reference builder that must produce the same, and Dart decodes `expected`. Rules:

- Replay `events` with the replay rules above. `status` is `active` or `paused`, or `ended` for a completed (`end_reason` `completed`) or abandoned (`discarded`) session. `owner`, `name` and `started_at_utc` come from `workout_started`; `last_sequence` is the highest sequence.
- A pause lasts until the next `workout_resumed`, `workout_completed` or `workout_abandoned`. `paused_seconds` is the whole seconds of the finished pauses and is left out when 0; `paused_at_utc` is the start of the running pause, only while `paused`.
- `rest_deadline_utc` is the deadline of the last `rest_started`, unless a later `rest_cleared`, `set_logged`, `workout_paused`, `workout_completed` or `workout_abandoned` ended it. The state may name a deadline that has passed; the phone compares it to its own clock.
- `exercises` follow the template in position order, sets in position order. A set the replay did not touch is `planned` with `input_unit` (the binding unit) and its targets as `reps`, `duration_seconds` and `load_grams` (a target of 0 or none is left out) and, when the template has one from 1 to 3600, `rest_seconds`. A completed set has its last values, its last `input_unit` and `kind` (`load_grams` left out when 0); a skipped set has `kind` and no values.
- `current_set_id` is the first planned set in that order, left out for an ended session or when none is left.
- `applied_command_ids` and `rejected_commands` come from the context (oldest first); the newest 20 are kept.

## Replay cases

`cases/replay/<name>.json` holds `events` (workout_sync v2 envelopes) and the `expected` result of replaying them. Swift (`WorkoutReplay.swift`) and an independent reference in `tool/test_watch_link_contract.py` must produce exactly that result; there is no Dart replay. Rules:

1. Drop events whose `event_id` was already seen (the first copy wins), then sort by `sequence`. Delivery order never matters.
2. `sequence` starts at 0. `gaps` lists every number from 0 to the highest sequence that is missing. Events after a gap are still applied; nothing is invented.
3. Status starts `active`; `workout_paused`, `workout_resumed`, `workout_completed` and `workout_abandoned` set it in sequence order.
4. `set_logged` and `set_corrected` replace that set's values (`reps`, `duration_seconds`, `load_grams`, `rpe`) and mark it `completed`; `set_skipped` clears the values and marks it `skipped`. The later event in sequence wins, so a log after a skip counts, and a correction of a correction ends at the last one.
5. `history` lists the id of every event that touched the set, in sequence order. Sets are listed in the order they first appear.
6. `completed_sets` counts completed **working** sets (with reps or seconds). `volume_grams` is the sum of `reps x load_grams` over completed **working** sets with reps and a load. Warm-up sets and timed sets add nothing. This follows `calculateWorkoutHistory` in `apps/mobile/lib/features/progress/domain/workout_history_models.dart`, which excludes warm-ups.

## Completed cases

`cases/completed/<name>.json` holds the golden input and output of the watch's completed-workout builder (`CompletedWorkoutBuilder.swift`):

- `events`: workout_sync v2 envelopes of one finished session.
- `context`: `template` (the session's exercises and planned sets in snake_case: `name`, `plan_id`, optional `program_day`, `exercises[]` with `exercise_id`, `name`, `kind`, `muscle`, `position`, `sets[]` with `set_id`, `position`, `kind`, `target_*`, `rest_seconds`), `unit` (`kg` or `lb`), `account_key`, optional `healthkit_workout_uuid`, `message_id` and `sent_at_utc`.
- `expected`: the full `completed_workout` message.

Rules: only exercises with at least one completed or skipped set appear, in template position order; sets are completed or skipped ones only, in position order. A completed set has `completed_at_utc` of its last event; `load_grams` is left out when 0 or absent; a skipped set has only `input_unit` from the binding unit. `primary_muscles` is added only when the template's muscle is one of the cloud payload's muscle names; `muscle` is always kept. `original_offset_minutes` is the offset of the event `time_zone` at the start instant. Swift builds the message from `events` and `context` and must equal `expected`; Python checks every `expected` against the schema and the events against workout_sync v2; Dart decodes `expected` and runs the phone's `parseWorkout`.

## Health cases

`cases/health/<name>.json` holds the golden cases for the day rules the watch uses when it reads its own sleep, resting heart rate and HRV from HealthKit (ADR-0012 decision 4, amendment 2026-11-27). Each case has `description`, `utc_offset_minutes`, `now`, raw `sleep` segments (`from`, `to`, `stage`, `source_key`), `hrv` and `resting_hr` samples (`from`, `to`, `value`) and `expected`. `expected` holds `asleep_minutes`, `hrv_ms` and `resting_hr_bpm` for the local date of `now`, rounded like `watch_snapshots.dart`; a key is left out when the value is missing, never 0. Dart (`apps/mobile/test/watch/health_derivation_cases_test.dart`) runs every case through the phone's `buildNights`, `hrvDailyOf` and `reduceDaily`, and Swift (`WatchHealthDerivation`) must give the same numbers. The Dart runner needs a device zone equal to `utc_offset_minutes`, so every case uses offset 0 (CI runs in UTC). Time-zone handling (a night dated by its local end date, the local date of `now`) is covered by Swift unit tests in `WatchHealthDerivationTests`, not by these cases. One deliberate difference: a night that adds up to 0 asleep minutes is missing on the watch (the key is left out), while the phone shows 0; the Swift unit tests pin this, the cases do not include it. Steps are not here: HealthKit sums them and the watch only turns 0 into missing.

## Cross-language strictness

All three implementations (Python `jsonschema`, Dart, Swift) must agree on every fixture. Rules they share: patterns match the whole string (a trailing newline is rejected; the Python tests use `re.fullmatch` for `pattern` because `re.search` lets `$` match before a final newline, see `tool/contract_validation.py`); `date-time` is checked as a real RFC 3339 date-time (`rfc3339-validator` in `tool/requirements-ci.txt`); `minLength`/`maxLength` count Unicode code points (Dart `runes.length`, Swift `unicodeScalars.count`).

The Kotlin core in `apps/wear_os/core` runs the same fixtures and cases (`:core:test`).
