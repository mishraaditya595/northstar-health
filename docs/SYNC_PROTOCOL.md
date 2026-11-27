# Cross-device workout event protocol (watch -> phone -> Supabase)

**Status:** Adopted design, not implemented. See [ADR-0002](adr/0002-watch-workout-architecture.md), [ADR-0003](adr/0003-data-cloud-health.md), [ADR-0005](adr/0005-mandatory-auth-and-workout-sync.md), [Cloud Sync](CLOUD_SYNC.md).

## Two different durable transfers

```text
Apple Watch / Wear OS
  native workout engine (HealthKit / Health Services)
  watch-local session + sets + event outbox
             |
          retry, de-dup
             v
Flutter phone + ObjectBox
  inbox receipt + set state committed atomically
             |  ACK #1: phone DURABLY STORED event
             v
Supabase (signed-in only)
  workout aggregate snapshot + revision compare-and-set
             |  ACK #2: SERVER DURABLY STORED backup
             v
phone marks cloud outbox synchronized
```

ACK #1 never means the cloud has backed up data. Pairing/reachability isn't delivery. Watch never discards unacknowledged events, phone never acknowledges before ObjectBox commit, phone never drops cloud outbox because a request was merely sent.

## Portable v1 event envelope

```json
{
  "schema_version": 1,
  "event_id": "event-uuid",
  "workout_id": "workout-uuid",
  "session_id": "session-uuid",
  "origin_device_id": "installation-scoped-random-id",
  "sequence": 17,
  "type": "set_logged",
  "occurred_at_utc": "2026-10-23T11:05:00Z",
  "recorded_at_utc": "2026-10-23T11:05:01Z",
  "time_zone": "Asia/Kolkata",
  "payload": {
    "set_id": "set-uuid",
    "exercise_id": "exercise-uuid",
    "index": 2,
    "reps": 8,
    "load": 60,
    "unit": "kg"
  }
}
```

Other event types: `workout_started`, `workout_paused`, `workout_resumed`, `set_corrected`, `workout_completed`, `workout_abandoned`, `platform_workout_exported`. A correction references the original event and cannot silently overwrite history. Sanitize payloads before any operational logs/telemetry.

## Cloud workout payload (phone to Supabase, schema_version 1)

This is the JSON the phone sends to `sync_workout` and the server stores,
returns from `get_workout_changes` and includes in the account export. It is
separate from the portable watch event envelope above. Authority:
`northstar_private.validate_workout_v1`; extra keys are rejected.

Workout: `schema_version` (1), `workout_id`, `origin` (`northstar_phone` or
`beyondrep_watch`, case sensitive; anything else is rejected),
`status` (`completed`), `name`, `started_at_utc`, `completed_at_utc`,
`original_offset_minutes`, `exercises` (at most 120).

Exercise: `id`, `name`, `position`, `sets` (at most 300) are required.
Optional: `muscle` (logged group text), `equipment` (text),
`primary_muscles` and `secondary_muscles`.

- `primary_muscles` and `secondary_muscles` are arrays of the 14 muscle names
  `chest, shoulders, biceps, forearms, abs, obliques, quads, calves, traps,
  lats, lowerBack, triceps, glutes, hamstrings` (exact, case sensitive). At
  most 14 entries each, no duplicates, no muscle in both arrays, and
  `secondary_muscles` may be non-empty only when `primary_muscles` is.
- **Omission rule:** the phone sends both arrays only when the exercise
  snapshot has at least one primary muscle (a catalogue exercise). Workouts of
  custom exercises and workouts logged before muscles existed keep exactly the
  payload they always had, so older data and replays are unchanged.
- The two arrays add up to roughly 300 bytes per exercise at most, counted toward the 64 KiB payload limit that the outbox size check and the server already enforce.
- The restore parser applies the same rules and rejects the whole page with
  code `invalid_exercise_muscles`; the export passes the stored payload
  through unchanged.
- Deploy order: the migration `20261126010000_workout_exercise_muscles.sql`
  must be deployed before any app build that uploads the arrays. Older app
  builds reject unknown exercise keys when restoring, so update every install.

Set: `id`, `position`, `kind` (`working|warmup`), `status`
(`planned|completed|skipped`), `input_unit` (`kg|lb`) are required; optional
`reps`, `duration_seconds`, `load_grams`, `rpe`, `completed_at_utc`. A
completed set needs `completed_at_utc` and either `reps` or `duration_seconds`.

- `duration_seconds` (timed exercises such as plank) is an integer from 1 to
  86400. A set never carries both `reps` and `duration_seconds`; the server
  (`invalid set duration`, `set has both reps and duration`), the restore
  parser (code `invalid_set_duration`) and the phone's local check all reject
  it.
- **Omission rule:** the phone sends `duration_seconds` only when the set has
  seconds, so every rep set keeps exactly the payload and request hash it had
  before. `schema_version` stays 1. The export passes the stored payload
  through unchanged.
- A completed timed set counts as a completed working set. Loaded volume and
  loaded-set counts use only sets with `reps`, so a timed set with a
  `load_grams` (accepted for a later weighted-carry mode) adds no volume.
- Deploy order: the migration `20261126020000_workout_set_duration.sql` must
  be deployed before any app build that uploads `duration_seconds`. Older app
  builds reject the unknown set key when restoring (`unsupported_field`, the
  whole page is refused), so update every install.
- Deploy order: the migration `20261127090000_workout_origin_beyondrep_watch.sql`
  must be deployed before any app build that uploads `beyondrep_watch`. Older
  app builds reject the unknown origin when restoring
  (`invalid_workout_origin`, the whole page is refused). Older builds also
  fail the whole account JSON export and conflict review once any watch
  workout exists in the cloud, so update every install.

## Watch link v1

Phone-to-watch and watch-to-phone messages (account binding, plans and health snapshots, live session state and commands, completed workouts, ACKs) are defined in `contracts/watch_link/v1`. Events inside them use `contracts/workout_sync/v2` (RPE, timed sets, catalogue exercise ids); `contracts/workout_sync/v1` stays as it was. The replay cases under `contracts/watch_link/v1/cases/replay` are the shared test for ordering, duplicates, gaps and corrections. See [ADR-0012](adr/0012-apple-watch-companion.md). The watch answers the phone's plans and health messages with an `ack` (ids and a result only); the phone shows "synced" only after hearing one (see the ADR-0012 amendment of 2026-11-27 and the [watch glance and sync status design](superpowers/specs/2026-11-27-watch-glance-redesign-and-sync-status-design.md)).

## Workout owner / platform writer matrix

| Origin | Owns detailed set journal | Phone ObjectBox | Health platform writer | Supabase coordinator |
| --- | --- | --- | --- | --- |
| BeyondRep phone session | Phone | Primary writer | Phone *if user opts in* | Phone |
| BeyondRep Apple Watch session | Watch during recording/disconnect | Idempotent receiver and durable backup | **Apple Watch HealthKit** only if watch saved HKWorkout; phone skips | Phone after watch transfer |
| BeyondRep Wear OS session | Watch during recording/disconnect | Idempotent receiver and durable backup | **One designated writer**, normally phone Health Connect | Phone after watch transfer |
| Imported third-party platform workout | Health platform | Optional local display reference, not BeyondRep set log | Already owned by third party; **never re-export** | **Not backed up** as BeyondRep log |

Origin is stable across reconnection; do not arbitrarily transfer active workout authority if two devices are open. Session ownership/lease, intentional takeover and revision conflicts must be specified in the implementation. A watch reset before ACK can destroy the only unsynced local copy; show pending backup state and do not promise restoration of those events.

## Live watch workout commands (stage 5a)

A phone command to a workout the watch owns carries a `command_id` (UUID) that never changes on a resend. The watch applies a `command_id` at most once per session, records the outcome durably in the same transaction as the resulting events, and reports it in the next `session_state` as `applied_command_ids` or `rejected_commands` (the last 20 of each). The journal table `applied_commands` is keyed by `(session_id, command_id)`; a session's rows are deleted when it is abandoned and when the phone acks its completed workout (a completed session keeps them until then, so a resent `finish` is a duplicate). When the phone resends a command the watch already applied (a duplicate), that id is listed in the next states even when it is older than the newest 20, so a retry of an old command is still confirmed. A `correct_set` (or `log_set`) for a set that was never logged becomes `set_logged` and starts the set's rest; for a logged set it becomes `set_corrected`. A planned set in `session_state` may carry the template's `rest_seconds`, which the phone offers on its rest button (90 s when absent). When a `completed_workout` is imported, the phone drops a live card with the same `started_at_utc` even if the `ended` state was lost. The phone resends a pending command every 5 s for at most 30 s, then shows it as not saved with a retry. A command with a wrong account key is ignored; one for another session is rejected as `unknown_session`. `session_state` is latest-wins and never queued. See `contracts/watch_link/v1/README.md`.

## Phone-owned workout and `workout_link` (stage 5b)

For a workout the phone owns, the phone sends `session_state` with `owner: phone` and applies the watch's `session_command` messages with the same rules as above, keyed by `command_id` and by effect (a repeated command that changes nothing is a no-op, also after a phone relaunch; `add_set` is the exception). The watch sends `join` right after its HealthKit session starts (without `session_id`, which it does not know yet), again once the first state names the session, and every 30 s while it has no state or only a stale one; the phone answers with its state at once, or with an `ended` state built from the stored workout when the session is no longer active (so a missed end is recovered). A repeated `add_set` command creates its set under a uuid derived from the command id, so a replay after a phone relaunch adds nothing. At finish the watch saves the one `HKWorkout` and queues a `workout_link` in its journal (resent with `transferUserInfo` until acked). The phone checks the account key, stores one receipt for the workout in one ObjectBox transaction and sends an `ack`; the ack for a link applies to the `workout_link` message id and removes it from the watch outbox. A link for an unknown or not yet completed workout gets no ack, so the watch resends it; a link for a deleted workout is acked `rejected` (`invalid`). The link carries no health values.

## Replay and consistency rules

1. Watch commits set/status and its outbox event in **one native device-local transaction**; no successful haptic/green check until saved.
2. Watch sends event UUID and per-session sequence. Receiver validates IDs, unit, schema version, owner/pairing and event shape; write domain update **and inbox dedupe receipt in one ObjectBox transaction**. For a completed watch workout the import is one ObjectBox transaction with the inbox receipt and the cloud outbox entry, then the `ack`.
3. Only then send an explicit ACK #1 for the accepted `event_id`. Retrying the same event must return the same receipt without duplicating a set.
4. Sequence gaps, clock drift, deleted set corrections and unsupported schema versions are handled explicitly; no wall-clock-only total ordering.
5. Phone's cloud outbox synchronizes **completed** workouts as stable revisioned aggregates under ADR-0005: BeyondRep phone workouts, and, after the phone's durable import, completed Apple Watch workouts with origin `beyondrep_watch` (ADR-0012). In-progress watch sessions, raw heart rate and the health snapshot are never backed up. Cloud operation UUID/revision is different from watch event UUID/sequence.
6. Server enforces authenticated conditional update, operation idempotency and owner isolation; ACK #2 is returned only after commit.
7. Account logout stops cloud transfers; no unknown account auto-association. Device reboot, backgrounding and network loss preserve pending queues.
8. Watch platform export receipt is transmitted with `platform_workout_exported`, and as `healthkit_workout_uuid` on `completed_workout`, so phone doesn't duplicate HealthKit `HKWorkout`. Android uses one elected writer. External record metadata never becomes a sync event of raw HR/SpO₂.
9. Never include raw watch sensor streams or platform health caches in Supabase workout DTO; they remain in health platforms.
10. Queue compaction requires durable receipt and documented retention; never discard only pending copy on timeout or UI shutdown.

## Failure and real-device test matrix

Watch off-phone for 90 minutes; reconnect and replay; both devices process-killed; timeout before/after phone commit; duplicate event and reordered correction; conflicting phone/watch set edit; stale local revision; day change/timezone drift; low storage and battery; watch re-pair/reset; platform workout saved but receipt lost; account switch; multi-phone restore, permission revocation and consent off. Confirm actual memory/battery/foreground-service behavior on watchOS and Wear OS hardware.

Transport candidates: native WatchConnectivity and Google Wearable Data Layer; any Flutter wrapper remains a **transport only**, never an end-to-end sync guarantee.
