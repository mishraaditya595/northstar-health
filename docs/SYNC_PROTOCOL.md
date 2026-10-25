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

## Workout owner / platform writer matrix

| Origin | Owns detailed set journal | Phone ObjectBox | Health platform writer | Supabase coordinator |
| --- | --- | --- | --- | --- |
| NorthStar phone session | Phone | Primary writer | Phone *if user opts in* | Phone |
| NorthStar Apple Watch session | Watch during recording/disconnect | Idempotent receiver and durable backup | **Apple Watch HealthKit** only if watch saved HKWorkout; phone skips | Phone after watch transfer |
| NorthStar Wear OS session | Watch during recording/disconnect | Idempotent receiver and durable backup | **One designated writer**, normally phone Health Connect | Phone after watch transfer |
| Imported third-party platform workout | Health platform | Optional local display reference, not NorthStar set log | Already owned by third party; **never re-export** | **Not backed up** as NorthStar log |

Origin is stable across reconnection; do not arbitrarily transfer active workout authority if two devices are open. Session ownership/lease, intentional takeover and revision conflicts must be specified in the implementation. A watch reset before ACK can destroy the only unsynced local copy; show pending backup state and do not promise restoration of those events.

## Replay and consistency rules

1. Watch commits set/status and its outbox event in **one native device-local transaction**; no successful haptic/green check until saved.
2. Watch sends event UUID and per-session sequence. Receiver validates IDs, unit, schema version, owner/pairing and event shape; write domain update **and inbox dedupe receipt in one ObjectBox transaction**.
3. Only then send an explicit ACK #1 for the accepted `event_id`. Retrying the same event must return the same receipt without duplicating a set.
4. Sequence gaps, clock drift, deleted set corrections and unsupported schema versions are handled explicitly; no wall-clock-only total ordering.
5. Phone's cloud outbox synchronizes **completed NorthStar phone workouts** as stable revisioned aggregates under ADR-0005; watch-origin session transfer/backup is deferred for its separate implementation. Cloud operation UUID/revision is different from watch event UUID/sequence.
6. Server enforces authenticated conditional update, operation idempotency and owner isolation; ACK #2 is returned only after commit.
7. Account logout stops cloud transfers; no unknown account auto-association. Device reboot, backgrounding and network loss preserve pending queues.
8. Watch platform export receipt is transmitted with `platform_workout_exported` so phone doesn't duplicate HealthKit `HKWorkout`. Android uses one elected writer. External record metadata never becomes a sync event of raw HR/SpO₂.
9. Never include raw watch sensor streams or platform health caches in Supabase workout DTO; they remain in health platforms.
10. Queue compaction requires durable receipt and documented retention; never discard only pending copy on timeout or UI shutdown.

## Failure and real-device test matrix

Watch off-phone for 90 minutes; reconnect and replay; both devices process-killed; timeout before/after phone commit; duplicate event and reordered correction; conflicting phone/watch set edit; stale local revision; day change/timezone drift; low storage and battery; watch re-pair/reset; platform workout saved but receipt lost; account switch; multi-phone restore, permission revocation and consent off. Confirm actual memory/battery/foreground-service behavior on watchOS and Wear OS hardware.

Transport candidates: native WatchConnectivity and Google Wearable Data Layer; any Flutter wrapper remains a **transport only**, never an end-to-end sync guarantee.
