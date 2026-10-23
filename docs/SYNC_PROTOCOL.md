# Phone–watch durable workout protocol (v0 design)

**Status:** Planning contract, not a running transport. Data models must remain portable among Dart, Kotlin, Swift and any later backend.

## Message envelope

Versioned command/event format containing:

```json
{
  "schema_version": 1,
  "event_id": "uuid-unique-across-devices",
  "workout_id": "uuid-cross-device",
  "session_id": "uuid-session",
  "origin_device_id": "installation-scoped-id",
  "sequence": 17,
  "type": "set_logged",
  "occurred_at_utc": "2026-10-23T11:05:00Z",
  "recorded_at_utc": "2026-10-23T11:05:01Z",
  "time_zone": "Asia/Kolkata",
  "payload": {
    "exercise_id": "stable-exercise-id",
    "set_id": "uuid-set",
    "index": 2,
    "reps": 8,
    "load": 60.0,
    "unit": "kg"
  }
}
```

Other event types: `workout_started`, `workout_paused`, `workout_resumed`, `set_corrected` (references original event), `workout_completed`, `workout_abandoned`. Distinguish authoritative watch-sensor observations from manually entered reps/load; preserve source timestamps and metric units. Avoid personally identifying persistent device identifiers in analytics.

## Consistency rules

1. On device, **commit journal update and outbox event in one transaction**. If DB commit fails, no success UI.
2. Durable queue retries on transport error / device disconnect / app restart; exponential backoff with bounds.
3. Receiver validates version, origin, permission, IDs, units, time fields and payload; stores event once by `event_id` and records receipt atomically before ACK.
4. ACK identifies durable receiver receipt, **not** just WatchConnectivity/Data Layer delivery; backend sync (if ever added) has separate acknowledgment.
5. Reorder/dedup by per-session sequence where possible and reconcile gaps. Clocks may drift; never sort solely by wall-clock timestamp.
6. Corrections are new events referencing previous ID; do not silently clobber completed set histories. Resolve conflicting edits deterministically with auditability/user confirmation as appropriate.
7. Device never wipes unacknowledged outbound journal simply because phone is paired; explicit retention and safe-compaction after acknowledgments and restore tests.
8. Plan transfer and workout-event transfer use independent versioning/cursors. A late plan update must not rewrite a workout already in progress.
9. HealthKit/Health Connect imports are **not** assumed equivalent to watch-recorded workout events. Deduplicate by source/sample IDs when merging sources.
10. Encrypt transfers and on-device sensitive data per platform; pair authentication and permission revocation must be explicitly designed. No health payloads in telemetry.

## Test matrix

Disconnect mid-set, both endpoints killed/restarted, replayed event, reordered messages, out-of-order correction, identical event delivered via direct watch and health aggregation, incorrect units, daylight-saving transitions, watch out of storage, low battery and corrupted local queue. Track queue depth and recovery locally without logging PHI.

Transport candidates: Apple WatchConnectivity, Google Wearable Data Layer; optional wrappers require independent device verification. No cross-watch DB file sharing.
