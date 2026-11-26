# BeyondRep watch link v1

**Source of truth:** [message.schema.json](message.schema.json). Phone to Apple Watch and watch to phone messages. Workout events travel inside `workout_event` using [workout_sync/v2](../../workout_sync/v2/README.md). Design and policy: [ADR-0012](../../../docs/adr/0012-apple-watch-companion.md), [SYNC_PROTOCOL.md](../../../docs/SYNC_PROTOCOL.md).

Every message has `schema_version` 1 (other versions are rejected, never read as v1), `message_id`, `type`, `sent_at_utc`, the 64-hex `account_key` (an HMAC of the user id; the raw id and email never reach the watch) and a `body`. Unknown keys are rejected at every level.

`health_snapshot` is the only message that may carry health values; the CI test checks that no other valid fixture mentions them. `completed_workout.workout` is the cloud workout payload with `origin` `beyondrep_watch`; its field rules follow `docs/SYNC_PROTOCOL.md` "Cloud workout payload". The codecs (Dart, Swift) check only `origin` and a string `workout_id` of that object. **The stage-4 phone import must run the existing cloud-payload validator, including the reps-or-duration rule, before anything enters the outbox.** A delivered message is not an acknowledgment: durability is the explicit `ack`.

Fixtures are fictional and synthetic. `$id` values use the reserved `.invalid` domain only so the schema can reference the v2 schema; nothing is hosted there.

## Replay cases

`cases/replay/<name>.json` holds `events` (workout_sync v2 envelopes) and the `expected` result of replaying them. Swift (`WorkoutReplay.swift`) and an independent reference in `tool/test_watch_link_contract.py` must produce exactly that result; there is no Dart replay. Rules:

1. Drop events whose `event_id` was already seen (the first copy wins), then sort by `sequence`. Delivery order never matters.
2. `sequence` starts at 0. `gaps` lists every number from 0 to the highest sequence that is missing. Events after a gap are still applied; nothing is invented.
3. Status starts `active`; `workout_paused`, `workout_resumed`, `workout_completed` and `workout_abandoned` set it in sequence order.
4. `set_logged` and `set_corrected` replace that set's values (`reps`, `duration_seconds`, `load_grams`, `rpe`) and mark it `completed`; `set_skipped` clears the values and marks it `skipped`. The later event in sequence wins, so a log after a skip counts, and a correction of a correction ends at the last one.
5. `history` lists the id of every event that touched the set, in sequence order. Sets are listed in the order they first appear.
6. `completed_sets` counts completed **working** sets (with reps or seconds). `volume_grams` is the sum of `reps x load_grams` over completed **working** sets with reps and a load. Warm-up sets and timed sets add nothing. This follows `calculateWorkoutHistory` in `apps/mobile/lib/features/progress/domain/workout_history_models.dart`, which excludes warm-ups.

## Cross-language strictness

All three implementations (Python `jsonschema`, Dart, Swift) must agree on every fixture. Rules they share: patterns match the whole string (a trailing newline is rejected; the Python tests use `re.fullmatch` for `pattern` because `re.search` lets `$` match before a final newline, see `tool/contract_validation.py`); `date-time` is checked as a real RFC 3339 date-time (`rfc3339-validator` in `tool/requirements-ci.txt`); `minLength`/`maxLength` count Unicode code points (Dart `runes.length`, Swift `unicodeScalars.count`).
