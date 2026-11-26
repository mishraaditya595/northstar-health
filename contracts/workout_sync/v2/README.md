# BeyondRep workout sync wire protocol v2

**Source of truth:** [envelope.schema.json](envelope.schema.json). Same envelope as [v1](../v1/README.md) with `schema_version` `2`. v1 is unchanged; nothing ships v1, so there is no migration. A v2 reader rejects any other version (never reads v1 as v2) and the reverse. Design: [ADR-0012](../../../docs/adr/0012-apple-watch-companion.md).

## What changed from v1, and why

- **Set values match the cloud workout payload:** `position`, `kind` (working|warmup), `input_unit`, optional `reps`, `duration_seconds` (timed sets), `load_grams` (integer grams) and `rpe` (1 to 10 in half steps). v1 required `reps`, `load` and `unit` and forbade extra keys, so RPE and timed sets did not fit. A set needs `reps` or `duration_seconds`.
- **`exercise_id` is any string of 1 to 128 characters,** so catalogue ids such as `builtin.v1.synthetic-move-1` are valid.
- **New events:** `exercise_added`, `set_skipped`, `rest_started` (wall-clock `deadline_utc`) and `rest_cleared`.
- **`workout_started`** carries `name`, `owner` (watch|phone), the 64-hex `account_key` (an HMAC; never the user id or email), and optional `plan_id` and `program_day`.
- Corrections stay new events (`set_corrected` with `supersedes_event_id`); history is never mutated.

No heart rate or other sensor value appears in any event; the CI test checks the valid fixtures. Fixtures use fictional synthetic identifiers only.
