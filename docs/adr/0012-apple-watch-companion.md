# ADR-0012 — Apple Watch companion

**Status:** **Accepted** — approved by the project owner on 2026-11-26.
**Amends:** [ADR-0005](0005-mandatory-auth-and-workout-sync.md) (watch-origin workouts are backed up, see decision 3), [SYNC_PROTOCOL.md](../SYNC_PROTOCOL.md) rule 5 and [HEALTH_DATA.md](../HEALTH_DATA.md) (health snapshot exception, decision 4). Design: [Phase 4 design](../superpowers/specs/2026-11-26-phase-4-watch-and-tablet-design.md).

## Decisions

1. **Native companion.** The Apple Watch app is a native SwiftUI companion embedded in the iPhone app. Wear OS is deferred to its own later phase and reuses the same contracts.
2. **One `HKWorkout` per watch session.** The watch writes exactly one `HKWorkout` (traditional strength training) for every session it runs a workout session for, including phone-owned sessions it joins (spec 5.6), with workout share permission on the watch, and records its UUID in a `platform_workout_exported` event. The phone never writes a second one.
   - **Amendment, 2026-11-27:** the HealthKit workout UUID travels in the `completed_workout` body field `healthkit_workout_uuid` (stage 4a), not in a `platform_workout_exported` event.
3. **Completed watch workouts are backed up once, by the phone.** After the phone's durable import, a completed watch workout goes through the same outbox and `sync_workout` RPC as a phone workout, with cloud `origin` `"beyondrep_watch"`. In-progress watch sessions, raw heart rate and the health snapshot are never backed up. The Supabase migration and restore/export changes land with stage 4, before any build uploads this origin.
4. **Health scores stay on the phone.** The phone computes every score. The watch keeps only today's `health_snapshot`, on the watch, cleared at local midnight and on sign out, never synced, backed up, logged or sent to telemetry. Missing values stay missing, never zero.
   - **Amendment, 2026-11-27 (approved by Adi):** the watch also keeps the 7 days ending today, the phone's usual values (resting heart rate and HRV baseline means) and the readiness wording, all inside today's `health_snapshot`. Everything is still computed only on the phone, replaced on every snapshot, cleared at local midnight and on sign out, and never synced, backed up, logged or sent to telemetry. The `ack` the watch sends back carries only message ids and a result, never health values. Design: [watch glance redesign and sync status](../superpowers/specs/2026-11-27-watch-glance-redesign-and-sync-status-design.md).
5. **Accounts on the watch.** The watch has no Supabase session and never sees the user id or email. It holds an HMAC-SHA-256 account key (key `beyondrep.watch.account.v1`, message the user id, lowercase hex). The phone accepts a watch workout only when the key matches the signed-in account.
6. **Session ownership.** The device that starts a session owns it. The other device sends commands. A later edit of the same set supersedes the earlier one (`set_corrected`); the earlier event stays in the history. Ownership does not transfer in this phase.
7. **Revisit trigger.** A shared native formula library (C++/Rust) is reconsidered only if the watch has to compute a score itself. Until then shared logic is checked by the language-neutral files under `contracts/`.

## Consequences

- New contracts: `contracts/workout_sync/v2` (RPE, timed sets, catalogue ids) and `contracts/watch_link/v1`. `workout_sync/v1` is unchanged.
- ADR-0011 rule 3 (outside-workout dedup) is amended in stage 4.
- Stage 4a (phone side of workout import): the migration `20261127090000_workout_origin_beyondrep_watch.sql` lets the server accept the cloud origin `beyondrep_watch`. The phone imports a `completed_workout` atomically (workout, receipt and outbox entry in one ObjectBox transaction) and sends the `ack` only after the commit; a workout for another account gets no ack, so the watch keeps it. The `completed_workout` body gained an optional `program_day`. ADR-0011 rule 3 is amended: workouts from the watch app's own HealthKit source, and any workout whose platform UUID is in a stored receipt, are not outside workouts. The account-deletion wipe is persisted on the phone and resent until the watch acks it.
- Stage 4c: heart rate and active energy for a watch workout are read fresh on the phone through the receipt's HKWorkout UUID and are never stored, uploaded or exported. The watch drops a binding the phone has not refreshed in 90 days, with a clear tombstone, and keeps at most 20 tombstones.
- Nothing here is released or device-verified.
