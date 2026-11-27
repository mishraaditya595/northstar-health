# Phase 5: save phone workouts to Apple Health / Health Connect

**Date:** 2026-11-27 · **Status:** draft for Adi's review (builder check done) · **Builds on:** ADR-0003 (WorkoutHealthExport), ADR-0008 (reads), ADR-0011 (outside workouts), ADR-0012 (Apple Watch) · **New ADR:** ADR-0014

## 1. Intent

`docs/ROADMAP.md` Phase 5: an opt-in write of one BeyondRep-owned workout summary, with export receipts and retry/reconciliation, never double writing the Apple Watch `HKWorkout`; imported workouts stay read-only; resolve edit/delete behaviour before shipping.

Why: user-owned data and a store-ready app. A user who logs on the phone should see that training in Apple Health / Health Connect (Fitness history, other apps), the same way watch workouts already appear there.

## 2. Goals, non-goals, anti-goals

**Goals**
- One switch per account: "Save workouts to Apple Health" (iOS) / "Save workouts to Health Connect" (Android). Off by default.
- When on, every completed, non-deleted phone workout (origin `northstar_phone`) on this phone is saved once, **including all past ones** (Adi's decision, 2026-11-27), and every new one after it finishes.
- A durable per-workout receipt in ObjectBox, so a crash, a denied permission or an offline/unavailable store is retried and never leaves a copy.
- Deleting a workout in BeyondRep removes our copy from the health store.
- A workout the Apple Watch saved is never written again by the phone, including the stage 5b case where the watch's `workout_link` arrives after the phone already saved.

**Non-goals**
- Heart rate, calories, distance, sets or reps in the written record. The phone has none of its own and we never fabricate them (ADR-0003). Wear OS stage 3 (other thread) adds HR/calories for Galaxy Watch workouts later on top of this writer.
- Writing watch workouts (`beyondrep_watch`): the watch already saved them.
- Writing outside workouts read from other apps (ADR-0011): never.
- Uploading anything about the export to Supabase. Receipts are local only.
- Background export while the app is not running.

**Anti-goals (a failure even if it works)**
- Any duplicate entry in Apple Health / Health Connect for one BeyondRep workout.
- Our own saved workouts showing back up as "outside workouts" or feeding training load twice.
- Asking for write permission before the user turns the switch on, or turning it on silently.
- A health value reaching the outbox, Supabase, export file, logs or analytics.

## 3. Constraints and findings

- `health` 14.0.0 (already a dependency, no new one) has `writeWorkoutDataUUID` with idempotent replace-on-rewrite on both platforms: iOS `WorkoutMetadata(syncIdentifier, syncVersion)` (`HKMetadataKeySyncIdentifier`/`HKMetadataKeySyncVersion`), Android `clientRecordId` + `clientRecordVersion`. A workout written again with the same id and a greater version replaces the earlier one. Deletes: `deleteByUUID` (iOS) and `deleteByClientRecordId` (Android). No native code is needed.
- HealthKit behaviour on an **equal** sync version (crash after the write, before the receipt) is not documented by the plugin. So before (re)writing a workout without a confirmed receipt on iOS, the exporter reads BeyondRep's own saved workouts in that time window and adopts a match (section 5.4).
- `platform_health_reader.dart` already drops workouts whose source is `in.beyondrep.app` or a child (`_isOwnSource`), so phone-written workouts never appear as outside workouts. Keep and test that.
- The watch's HKWorkout comes from `in.beyondrep.app.watchkitapp`. Watch receipts (`WatchWorkoutReceiptEntity.platformWorkoutUuid`) exist for watch-origin imports and for 5b `workout_link`s. Receipts are local, so a phone restored from the cloud does not know which phone workouts the watch joined; the overlap check (5.3) covers that.
- New permissions: iOS `WORKOUT` share (write) plus `WORKOUT` read (needed for the overlap/adopt checks); Android `android.permission.health.WRITE_EXERCISE` (READ_EXERCISE already declared). `NSHealthUpdateUsageDescription` must change from "does not write" to a true sentence. Policy/permission change, so ADR-0014. `docs/PRIVACY_POLICY_INPUTS.md` and `RELEASE.md` store gates update.
- New ObjectBox entities: stable UIDs, generated code and `objectbox-model.json` committed, old-database migration test.
- Health read, health write and cloud backup stay three independent opt-ins (`HEALTH_DATA.md`). The export switch does not require the read connection.
- An energy-score thread and a Wear OS thread also touch health code. Keep edits to shared files (`platform_health_reader.dart`, `health_reader.dart`, `health_page.dart`, the manifest, `Info.plist`) small and additive.

## 4. Approaches considered

1. **Derive what to export from the workouts table, receipts record only what was written (chosen).** An exporter pass compares completed phone workouts with receipts and does the missing writes/deletes. The finish and delete transactions are not touched, so the sync/outbox contract is untouched. Backfill, retries and new workouts are the same code path. Crash safety comes from the platform's idempotent ids plus the adopt check.
2. **Enqueue an export job in the finish transaction (like the cloud outbox).** Mirrors `SyncOutbox`, but it edits the most sensitive transaction in the app, still needs a scan for backfill and for workouts changed by restore/conflict recovery, and gains nothing because the platform write is idempotent anyway.
3. **Native Swift/Kotlin bridges.** More control over HealthKit metadata, but the plugin already exposes everything needed; more code and a second permission path.

## 5. Design

### 5.1 Settings and first use

- New ObjectBox entity `HealthExportSettingEntity { ownerAccountId @Unique, enabledAtMs }`: a row means the account turned saving on. Never synced. Removed by the account local cleanup like other account rows.
- Health tab, in the settings area next to Disconnect: a switch row "Save workouts to Apple Health" / "...to Health Connect" with a one-line status ("42 saved", "3 waiting", "Allow access in Settings" when denied). Shown on both platforms whenever the health store is available (independent of the read connection). Component kit only.
- Turning it on opens a kit bottom sheet first: "BeyondRep will save each workout you finish on this phone to Apple Health as Strength training, with its name, start and end. Your past workouts here are saved too. Heart rate and calories are not included. Apple Watch workouts are already in Apple Health and are not saved twice." Buttons: "Turn on" (then the platform permission prompt) and "Not now".
- If the user denies, the switch row stays on with "Allow access in Settings" and an action that opens the health settings (existing `openSettings`). *(My call: keep the user's intent; turning it off is explicit.)*
- Turning it off: no more writes and no deletes; entries already saved stay in the health store. Receipts are kept, so turning it on again does not rewrite them.

### 5.2 What is exported

A workout is wanted in the health store when all hold:
- status completed, `completedAtMs` set, `deletedAtMs` null, origin `northstar_phone`;
- no `WatchWorkoutReceiptEntity` for its uuid with a `platformWorkoutUuid` (the watch saved it, 5b);
- not marked `skippedWatch` by the overlap check (5.3).

It includes workouts restored from the cloud (Adi: all past workouts). Record written: activity type strength training (iOS `TRADITIONAL_STRENGTH_TRAINING`, Android `STRENGTH_TRAINING`), start = `startedAtMs`, end = `completedAtMs`, title = workout name (Android only), iOS metadata `workoutBrandName: 'BeyondRep'`, `indoorWorkout: true` *(my call)*, id = lowercase workout uuid, version = the workout's `updatedAtMs` *(my call: unlike the local `revision`, which restarts at 1 when a workout is restored on another phone, it only grows, so a rewrite from any iPhone on the same Apple ID carries a greater version)*. Android zone offsets from `originalOffsetMinutes`. No energy, no distance.

### 5.3 Never duplicating the watch (iOS)

- Before the first write of a workout, read workouts in its window from source `in.beyondrep.app.watchkitapp` (exact or child of `in.beyondrep.app.` other than the phone itself). If one overlaps by the existing 50% rule (`outside_workouts.dart`), the receipt becomes `skippedWatch` and nothing is written. Covers 5b links still in flight and phones restored from the cloud.
- A `workout_link` (or watch import) that arrives for a workout whose receipt is `confirmed`: the phone deletes its own copy and the receipt becomes `supersededByWatch`. Triggered from the existing `onLinked` callback.
- *(My call)* If the iPhone has a paired Apple Watch with the app installed (existing watch status), a workout is not exported until 10 minutes after it finished, which removes most brief double entries in the 5b case.
- HealthKit never tells an app whether read access was granted; a denied Workout read returns nothing, so the overlap and adopt checks find nothing. *(My call: still write. The same-phone 5b case is covered by the watch receipt, the 10-minute delay and the superseded delete; the remaining risk is a phone restored from the cloud with Workout read denied, for workouts the watch joined. ADR-0014 records it.)*
- Android has no watch writer in this phase.

### 5.4 Receipts and the state machine

New ObjectBox entity `HealthExportReceiptEntity`:
`workoutUuid @Unique`, `platform` (`healthkit` | `health_connect`), `state`, `exportedRevision` (int, 0 = none), `platformRecordId` (HK UUID on iOS; on Android the clientRecordId), `attempts`, `lastAttemptAtMs`, `updatedAtMs`. Platform ids are local only, never synced or logged.

States (subset of `HEALTH_DATA.md`'s machine): `writing` → `confirmed`; `failedRetryable`; `blocked` (permission denied, not retried until access changes); `skippedWatch`; `supersededByWatch`; `deleting` → row removed.

Pass, for each wanted workout without a `confirmed` receipt at its current revision:
1. Commit receipt `writing` (revision R) before calling the platform.
2. iOS, before every first write (no `confirmed` receipt yet, including an uncertain crash and a phone restored from the cloud whose Apple Health already holds the copy another iPhone wrote, since iCloud syncs Health between iPhones): read our own source's workouts in the window; if one matches the start/end, adopt its UUID → `confirmed` at R without writing *(my call)*. Android needs no adopt step (same clientRecordId upserts, Health Connect is per device).
3. Call `writeWorkoutDataUUID`. Non-empty UUID / true → `confirmed` with R and the id. Permission error → `blocked`. Other error or empty result → `failedRetryable` (attempts+1).

A confirmed workout whose revision later grows (conflict recovery, restore) is written again with the new version, replacing the earlier entry.

Deleted workouts with a `confirmed` (or `writing`) receipt: receipt `deleting`, delete by id (iOS `deleteByUUID`, Android `deleteByClientRecordId` for WORKOUT), then remove the receipt. A deleted workout with no receipt (deleted on another phone, tombstone restored here) gets the same own-copy lookup on iOS and is deleted if found *(my call)*. Runs even when the switch is off? *(My call: no; off means hands off. The receipt stays and is acted on if turned back on.)*

When the pass runs: after a workout finishes, after a workout is deleted, when the switch turns on, on app resume, after a `workout_link`, and when an account signs in. One pass at a time; at most 50 writes per pass, oldest first, so a large backfill spreads over a few passes without blocking the UI *(my call)*. A pass does nothing when signed out, switch off, or the store is unavailable. Retry backoff for `failedRetryable`: next resume, then capped at once an hour.

### 5.5 Code layout (builder may adjust names)

- `lib/features/health/data/health_workout_writer.dart`: `HealthWorkoutWriter` interface (`writeAvailability`, `requestWriteAccess`, `hasWriteAccess`, `write(HealthWorkoutRecord) -> WriteResult`, `delete(platformRecordId)`, `ownWorkoutsIn(window)`, `watchWorkoutsIn(window)`) and `PlatformHealthWorkoutWriter` over `health`. `HealthWorkoutRecord` is a small value type the Wear OS stage can extend with optional HR samples and calories.
- `lib/features/health/data/health_export_receipt_entity.dart`, `health_export_setting_entity.dart`, an ObjectBox repository.
- `lib/features/health/domain/workout_health_export.dart`: pure planner (workouts + receipts + watch receipts → list of write/delete/skip actions). Most tests live here.
- `lib/features/health/application/workout_health_export_controller.dart`: Riverpod controller running passes, the status line, triggers.
- Health page switch row and first-use sheet.
- iOS `Info.plist` `NSHealthUpdateUsageDescription`: "BeyondRep saves the workouts you finish on this phone to Apple Health when you turn this on in the Health tab." Android manifest `WRITE_EXERCISE`. Update `tool/test_ios_privacy_strings.py` if it pins the old text.
- ADR-0014; `HEALTH_DATA.md`, `OBJECTBOX.md` (receipt), `PRIVACY_POLICY_INPUTS.md`, `RELEASE.md` device rows, `ROADMAP.md`, `CLAUDE.md` "Not implemented" line.

### 5.6 Account boundaries

Settings and receipts live in the account's ObjectBox partition; another account on the same phone has its own switch and receipts. Account deletion keeps entries already in Apple Health (they are the user's health records now) *(my call)*; local receipts go with the partition.

## 6. Tests (builder)

Planner: each eligibility rule; watch receipt skip; revision bump rewrites; deleted with/without receipt; switch off does nothing; 50 cap and oldest-first order. Controller with a fake writer: crash after write before confirm (Android upsert, iOS adopt), permission denied → blocked then retried after access, unavailable store, link after confirm → delete + superseded, overlap → skippedWatch, account switch mid-pass, signed out. Reader: phone-written source never shows as outside workout. ObjectBox: old database opens with the new entities. Guards: no export field in outbox payloads or the JSON export; design-kit guard passes. Device rows (not runnable here): first-use permission prompt on iPhone and Android, backfill of a real history, delete removes the entry, 5b with the watch joined leaves one entry, Health Connect not installed.

## 7. Left to the builder

Exact file/class names, the status-line wording beyond the above, how the controller is wired into existing triggers, the precise window used for the own/watch reads (workout start-1 min to end+1 min suggested).
