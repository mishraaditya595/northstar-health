# ADR-0016 — Log a weight to Apple Health and Health Connect

**Status:** **Accepted** 2026-11-28. Implemented in source, **not released or device-verified**.
**Builds on:** [ADR-0008](0008-daily-health-summary-reads.md) (daily health reads) and [ADR-0014](0014-save-workouts-to-health-platforms.md) (workout writes). Does not change ADR-0005 backup scope. Design: [`docs/superpowers/specs/2026-11-28-log-weight-design.md`](../superpowers/specs/2026-11-28-log-weight-design.md).

## Context

People want to add a new weight from the app (a morning weigh-in) and see it in Apple Health or Health Connect. Writing a body measurement is a new write permission and a new kind of record, so it needs a numbered ADR. ADR-0014 allows workout summaries only.

## Decision

1. **Add a new entry, never edit.** A "Log weight" button on the Body card and the Body detail page, shown while health is connected. A sheet takes one number in kg, prefilled with the latest weight. The entry is timed now. Older entries and entries from other apps or scales are not edited or deleted.
2. **Validation.** 20.0 to 400.0 kg, one decimal, comma or point accepted. Pounds, other body measurements and choosing a date are out of scope.
3. **What is written.** One `WEIGHT` record in kilograms, recording method `manual`, timed now, with a fresh random v4 `clientRecordId` at `clientRecordVersion` 1. iOS writes through the `health` 14.0.0 plugin (`writeHealthDataUUID`). Android writes one manual-entry `WeightRecord` through a small native writer (`WeightWriter.kt`, channel `beyondrep/health_weight`, amended 2026-11-28), because the plugin's Android `ValueWriter` logs every written value to logcat at INFO; it logs nothing and its errors carry a code only. Deletes (Undo) still go through the plugin on both platforms.
4. **Permission on first Save only.** Write access is requested when the user first taps Save, never during connect. Write access only, on both platforms (`HealthDataAccess.WRITE` for the request and the check): iOS `HealthDataType.WEIGHT` share; Android `android.permission.health.WRITE_WEIGHT`, with the existing `READ_WEIGHT` left to the Connect flow. On Android the Health Connect SDK status is checked first; a missing Health Connect is a failed save, not a denial. On iOS a denial says to allow it under Sharing > Apps > BeyondRep in the Health app (iOS cannot deep-link there); Android keeps an Open Settings button. A denied request keeps the sheet open. The write is independent of the "Save workouts" switch of ADR-0014 and of the read connection.
5. **Only a non-empty record id is a success.** On iOS the plugin can return an empty or `"null"` id; on Android `WeightWriter.kt` replies a record id or an error code. Anything but a non-empty id is shown as failed and nothing is reported saved.
6. **Undo, once, in memory.** The snackbar "Saved to Apple Health" / "Saved to Health Connect" has Undo, which deletes that one entry (iOS by the returned HealthKit UUID with type `WEIGHT`, Android by client record id). The handle lives in memory only and is gone when the app closes. A failed Undo says to delete it in the Health app.
7. **Account boundary.** The account is re-checked before the write. Nothing account-scoped is stored.
8. **Nothing of ours stores the weight.** No ObjectBox, Supabase, outbox, JSON export, logs or telemetry. The health store is the only copy.
9. **Amends the AGENTS.md data-ownership line** "Only app-owned completed workout summaries may be exported..." for user-entered weight: one weight, typed and saved by the user, is written once per tap, needs no dedup receipt (nothing is retried or re-exported) and Undo deletes it. The AGENTS.md text itself needs owner approval and is raised in the PR; agents do not edit it.
10. **Undo is account-bound.** The handle remembers the account that saved it; after sign-out or an account switch Undo deletes nothing and reports failure.

## Consequences

- BeyondRep's own code logs no weight or record id. On iOS the `health` plugin prints the written record id (no value) to the device log (`debugPrint`); that is outside the app's control, as in ADR-0014. Android writes natively, so no weight value or id is logged on a write. On Android the plugin also logs the client record id (`Log.e`) when a delete fails, and `debugPrint` prints in release builds too.
- `package:health` is imported by one more file, `health_weight_writer.dart`, listed in the import guard test.
- The Play Console Health apps declaration must list `WRITE_WEIGHT`. App Privacy answers are unchanged because nothing is collected by us. `NSHealthUpdateUsageDescription` now also names weights. `tool/test_android_health_permissions.py` pins the manifest to exactly `WRITE_EXERCISE` and `WRITE_WEIGHT` as health writes (ADR-0015 later adds `WRITE_HEART_RATE` and `WRITE_TOTAL_CALORIES_BURNED` for Wear OS watch workouts).
- The design kit gains `showNsSheet(enableDrag:)`, `showNsMessageOn(messenger, ...)` and `nsMessengerOf(context)` so the snackbar outlives the sheet.
- Editing past entries, pounds, other measurements or storing weights need a new ADR.
- Status: implemented in source; device rows are open in [`docs/RELEASE.md`](../RELEASE.md).
