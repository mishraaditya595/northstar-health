# Log weight to Apple Health / Health Connect

**Date:** 2026-11-28 · **Status:** approved by Adi 2026-11-28 (short design, in the project thread) · **Builds on:** ADR-0008 (daily health reads), ADR-0014 (workout writes) · **New ADR:** ADR-0016

## 1. Intent

Adi: "I want people to edit their weight from the app and that reflects in Apple Health or Google health." Clarified: people **add a new weight measurement**, the moment being a **morning weigh-in**. The new entry goes into Apple Health (iOS) or Health Connect (Android), so the Health tab and the health app show the same latest weight.

## 2. Goals, non-goals, anti-goals

**Goals**
- A **Log weight** button on the Body card (Health tab) and on the Body detail page, shown whenever health is connected.
- A small sheet: one number field in kg, prefilled with the latest weight, "Save". The entry is timed now.
- After a save: the health overview refreshes (the new weight shows as latest) and a snackbar says "Saved to Apple Health" / "Saved to Health Connect" with **Undo**, which deletes that one entry.
- Weight write permission is asked on the first Save, separate from the read connection and from the workout-saving switch.

**Non-goals**
- Editing or deleting older entries, or entries from other apps or scales (the platforms only let an app change what it wrote, and Adi wants new measurements only).
- Pounds. Every weight in the app is kg today; lb can come later.
- A button on Today.
- Body fat, lean mass or any other body measurement.
- Choosing a different date or time.

**Anti-goals**
- Storing the weight anywhere of ours: no ObjectBox, Supabase, outbox, JSON export, logs or telemetry. The health store is the only copy (Adi: "perfect").
- Showing "saved" when the platform did not accept the entry.
- Asking for write permission during connect or before the user taps Save.

## 3. Constraints found

- `health` 14.0.0 has `writeHealthDataUUID(value, unit: KILOGRAM, type: WEIGHT, startTime, recordingMethod: manual, clientRecordId)` returning the platform record id, `deleteByUUID(uuid, type)` (iOS needs the type) and `deleteByClientRecordId` (Android). No native code needed. (Amended 2026-11-28: the plugin logs written values on Android, so the Android write is native; see ADR-0016 decision 3.)
- As with the workout writer (ADR-0014), Android turns a native failure into an empty or `"null"` result, so only a non-empty id is a success.
- `package:health` may be imported only by files listed in the import guard test; a new writer file must be added there.
- iOS: `NSHealthUpdateUsageDescription` must mention weight; `tool/test_ios_privacy_strings.py` checks it. Android: `android.permission.health.WRITE_WEIGHT` in the manifest and the Play Health apps declaration.
- The website privacy page still says the app "does not write or change anything" in Apple Health / Health Connect, which is already stale since ADR-0014.

## 4. Approaches

1. **`health` plugin write, nothing stored (chosen).** One small writer over the plugin, a controller that requests access, validates and writes, and a sheet from the design kit. Cheapest, no native code, fits "no health values stored".
2. Native Swift/Kotlin bridge: more code for nothing the plugin lacks. Dropped.
3. Keep a local log of entered weights and sync it to the store: breaks the no-health-values-on-disk rule and duplicates the store. Dropped.

## 5. Design

**Data flow.** Sheet → `WeightLogger.save(kg)` → checks range (20.0 to 400.0 kg, one decimal; comma accepted as decimal point) → if write access is missing, requests it (platform prompt) → `HealthWeightWriter.write(kg, at: now)` → on success refreshes the health overview and returns a `SavedWeight(recordId, clientRecordId)` kept in memory only for the snackbar's Undo → Undo calls `HealthWeightWriter.delete(...)` and refreshes again.

**Identity.** Each entry gets a fresh random UUID as `clientRecordId` on Android (delete by client record id); iOS deletes by the returned HealthKit UUID with `type: WEIGHT`. Recording method `manual` on both.

**Results shown.** Saved → snackbar with Undo. Denied → the sheet stays open with "Allow BeyondRep to write weight in Settings" and an Open Settings button (reusing the reader's `openSettings`). On iOS there is no deep link, so the button is hidden and the text is "Allow BeyondRep to write weight in the Health app: Sharing > Apps > BeyondRep." Permission is requested and checked with `HealthDataAccess.WRITE` on both platforms (no read access is asked). Failed or unavailable → "Couldn't save to Apple Health. Try again." and nothing changes. Undo failed → "Couldn't remove it. Delete it in the Health app."

**Account boundary.** Nothing account-scoped is stored. The button appears only when the current account's health connection is on.

**Docs.** ADR-0016; `docs/HEALTH_DATA.md`, `docs/PRIVACY_POLICY_INPUTS.md`, `docs/RELEASE.md` device rows, the website privacy page (also fixing the stale "does not write" line to cover workouts and weight), CLAUDE.md project state.

## 6. Left to the builder

Widget names and file split inside `features/health/`, exact copy of captions, test layout, how the sheet's field reports validation errors (inline under the field).

## 7. Calls I made (Adi can change)

kg only; no Today button; 20 to 400 kg range; entry timed now; Undo instead of editing past entries.
