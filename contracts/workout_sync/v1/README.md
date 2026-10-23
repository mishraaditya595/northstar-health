# NorthStar workout sync wire protocol v1

**Source of truth:** [envelope.schema.json](envelope.schema.json). This schema is the **watch -> phone** event envelope for planned future integration, not proof that either watch app currently transmits events. Implement domain operations/repositories separately from platform transport.

## Ownership and guarantees

1. Recording device persists a completed set and outbound event locally in a single native transaction.
2. Phone validates authenticated pairing/owner identity and schema, then saves imported workout data + inbox dedup receipt **atomically in ObjectBox**.
3. Phone responds ACK #1 only after durable local commit; duplicate `event_id` returns the same acknowledgment. Transport delivery/reachability is not acknowledgment.
4. Phone's Supabase backup is a separate, optional, authenticated **completed-workout-only** workflow; server ACK #2 is independent of watch ACK #1.
5. Watch-origin HealthKit `HKWorkout` and designated Wear OS platform writer are identified to prevent duplicate summary exports.

## Schema and compatibility

- Each message has `schema_version = 1`, RFC 4122 UUID identities, origin installation ID, strictly increasing per-session `sequence` from a recording device, actual/recorded UTC timestamps and IANA timezone context.
- Supported event types: workout start/pause/resume/completion/abandonment, set logged/corrected, and platform workout export receipt.
- Set events contain load/unit and manually entered reps, **never a raw sensor stream**. HealthKit / Health Connect hold physiological measurements.
- Corrections are new events referencing `supersedes_event_id`; never mutate an acknowledged event invisibly.
- Unknown future versions must be rejected/queued for upgrade, not silently treated as v1.
- `format: uuid` and `format: date-time` are checked in the CI fixture suite; non-schema semantics (monotonic sequence, paired identity, stale events, clock skew, authorization and exactly-once effect) are future integration-test responsibilities.
- This JSON example design needs Swift/Kotlin/Dart serializers tested on the same fixtures once transport is implemented. None has been written in this structural PR.

`fixtures/valid/` and `fixtures/invalid/` contain **fictional synthetic identifiers only**; change them with a protocol-version compatibility review. See [docs/SYNC_PROTOCOL.md](../../../docs/SYNC_PROTOCOL.md).
