# Log Weight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user log a new weight (kg) from the Health tab and Body detail page; it is written to Apple Health / Health Connect and can be undone from the snackbar.

**Architecture:** A `HealthWeightWriter` over `package:health` writes and deletes one weight sample. A `WeightLogger` service validates input, asks for write access on first save, writes, refreshes the health overview and returns an in-memory handle for Undo. A design-kit sheet opened from the Body card and Body detail page drives it. Nothing is stored by BeyondRep.

**Tech Stack:** Flutter 3.47.7, Riverpod, `health` 14.0.0, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-28-log-weight-design.md`

## Global Constraints

- No weight value, record id or timestamp is written to ObjectBox, Supabase, the outbox, the JSON export, logs or telemetry. No `debugPrint`/`log` of values or ids in BeyondRep code.
- kg only; accepted range 20.0 to 400.0 kg inclusive; input rounded to one decimal; `,` accepted as the decimal point.
- Entry time = `wallClockProvider()` at save; recording method `RecordingMethod.manual`.
- Only a non-empty, non-`"null"` id from the plugin counts as saved (Android returns empty on any native failure).
- UI uses only `lib/core/design/` (`NsTextField`, `showNsSheet`, `showNsMessage`, kit buttons); `test/design_kit_guard_test.dart` must stay green.
- `package:health` imports are allowed only in `platform_health_reader.dart`, `health_workout_writer.dart` and the new `health_weight_writer.dart`.
- Copy (exact): button `Log weight`; sheet title `Log weight`; field label `Weight (kg)`; save button `Save`; success `Saved to Apple Health` / `Saved to Health Connect`; snackbar action `Undo`; out of range `Enter a weight between 20 and 400 kg`; denied `Allow BeyondRep to write weight in Settings` with button `Open Settings`; failure `Couldn't save to Apple Health. Try again.` / `Couldn't save to Health Connect. Try again.`; undo failure `Couldn't remove it. Delete it in the Health app.` / `Couldn't remove it. Delete it in Health Connect.`
- From `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test` pass before the PR. From the repo root: `python3 -m unittest discover -s tool -p 'test_*.py'`.

## Review Focus

1. Account switched or health disconnected while the sheet is open: Save must not write for the new account's view; the logger checks the overview owner is unchanged before writing. (Test in Task 2.)
2. Undo tapped after the user left the page: the delete still runs once and the overview refreshes; a second tap does nothing. (Test in Task 2.)
3. Double-tap on Save: exactly one write. (Test in Task 3.)
4. Input `"72,4"`, `" 72.45 "`, `"abc"`, `""`, `"19.9"`, `"400.04"`: parsed to 72.4, 72.5 (rounded), rejected, rejected, rejected, 400.0 (rounds into range). (Test in Task 2.)
5. Body section is a gap (weight read denied or no data): the Log weight button still shows and works. (Test in Task 3.)

---

### Task 1: Platform weight writer

**Files:**
- Create: `apps/mobile/lib/features/health/data/health_weight_writer.dart`
- Modify: `apps/mobile/test/health/health_import_guard_test.dart` (add the new file to the allowed set)
- Test: `apps/mobile/test/health/health_weight_writer_test.dart`

**Interfaces:**
- Consumes: `HealthWriteResult`, `HealthWriteOk`, `HealthWriteDenied`, `HealthWriteFailed`, `HealthWriteUnavailable` from `health_workout_writer.dart`; `UuidFactory`/`SecureUuidFactory` from `lib/core/ids/uuid_factory.dart`.
- Produces:
  ```dart
  class SavedWeight { const SavedWeight({required this.platformRecordId, required this.clientRecordId}); final String platformRecordId; final String clientRecordId; }
  abstract interface class HealthWeightWriter {
    bool get isIos;
    Future<bool> hasWriteAccess();
    Future<bool> requestAccess();            // platform prompt for weight
    Future<HealthWriteResult> write(double kg, DateTime at);   // HealthWeightWriteOk on success
    Future<bool> delete(SavedWeight saved);
  }
  class HealthWeightWriteOk extends HealthWriteOk { const HealthWeightWriteOk(super.platformRecordId, this.clientRecordId); final String clientRecordId; }
  class PlatformHealthWeightWriter implements HealthWeightWriter { PlatformHealthWeightWriter(Health health, {bool? isIos, UuidFactory? ids}); }
  final healthWeightWriterProvider = Provider<HealthWeightWriter>(...);
  ```

- [ ] **Step 1: Write failing tests** with a `_FakeHealth extends Fake implements Health` (pattern from `test/health/health_workout_writer_test.dart`):
  - `write sends kg, WEIGHT, manual, start == end == at, and a v4 clientRecordId` → asserts args `value == 72.4`, `unit == HealthDataUnit.KILOGRAM`, `type == HealthDataType.WEIGHT`, `recordingMethod == RecordingMethod.manual`, `startTime == endTime == at`, `clientRecordId` matches the UUID v4 regex; result is `HealthWeightWriteOk` with `platformRecordId == 'new-uuid'`.
  - `empty or "null" id is a failure` → `writeResult = ''` and `'null'` both give `HealthWriteFailed`.
  - `permission HealthException is denied, UnsupportedError is unavailable, other errors are failed`.
  - `requestAccess asks WEIGHT with READ_WRITE` and `hasWriteAccess checks WEIGHT with WRITE on iOS, READ_WRITE on Android`.
  - `delete on iOS uses deleteByUUID(type: WEIGHT); on Android deleteByClientRecordId(WEIGHT, clientRecordId)`; returns the plugin's bool; a thrown error returns false.
  - Update the guard test expectation to include `lib/features/health/data/health_weight_writer.dart`.
- [ ] **Step 2: Run** `flutter test test/health/health_weight_writer_test.dart test/health/health_import_guard_test.dart` — expect FAIL (file missing).
- [ ] **Step 3: Implement** `health_weight_writer.dart`. Call `_health.configure()` once (memoised as in `PlatformHealthWorkoutWriter`). On Android, check `getHealthConnectSdkStatus() == sdkAvailable` before writing, else `HealthWriteUnavailable`. Use `writeHealthDataUUID`. Catch everything; no logging.
- [ ] **Step 4: Run** the same command — expect PASS.
- [ ] **Step 5: Commit** `feat(health): platform writer for one weight sample`.

### Task 2: Input parsing and the weight logger

**Files:**
- Create: `apps/mobile/lib/features/health/domain/weight_entry.dart`
- Create: `apps/mobile/lib/features/health/application/weight_logger.dart`
- Create: `apps/mobile/test/support/fake_health_weight_writer.dart`
- Test: `apps/mobile/test/health/weight_entry_test.dart`, `apps/mobile/test/health/weight_logger_test.dart`

**Interfaces:**
- Consumes: Task 1's `HealthWeightWriter`, `SavedWeight`, `HealthWeightWriteOk`, `healthWeightWriterProvider`; `healthOverviewProvider` (`.notifier.refresh()`, `.value?.ownerId` or the existing owner field), `healthOwnerIdProvider`, `wallClockProvider`, `healthReaderProvider.openSettings()`.
- Produces:
  ```dart
  // domain/weight_entry.dart
  const minWeightKg = 20.0; const maxWeightKg = 400.0;
  double? parseWeightKg(String input);   // null when not a number or out of range after rounding to 0.1
  // application/weight_logger.dart
  sealed class WeightSaveResult {}
  final class WeightSaved extends WeightSaveResult { WeightSaved(this.saved); final SavedWeight saved; }
  final class WeightInvalid extends WeightSaveResult {}
  final class WeightDenied extends WeightSaveResult {}
  final class WeightSaveFailed extends WeightSaveResult {}   // failed, unavailable, or account changed
  class WeightLogger { Future<WeightSaveResult> save(String input); Future<bool> undo(SavedWeight saved); Future<void> openSettings(); bool get isIos; }
  final weightLoggerProvider = Provider<WeightLogger>(...);
  ```

- [ ] **Step 1: Write failing tests.**
  - `weight_entry_test.dart`: `'72,4'→72.4`, `' 72.45 '→72.5`, `'abc'→null`, `''→null`, `'19.9'→null`, `'20'→20.0`, `'400.04'→400.0`, `'400.05'→null`, `'-70'→null`, `'1e2'→null` (digits and one separator only).
  - `weight_logger_test.dart` (ProviderContainer, `FakeHealthWeightWriter`, fixed `wallClockProvider`, faked overview controller that counts `refresh` calls, as in existing health controller tests):
    - `invalid input never touches the writer` → `WeightInvalid`, zero writer calls.
    - `with access: writes kg at now and refreshes once` → `WeightSaved`, one write `(72.4, fixedNow)`, `refresh` count 1, `requestAccess` not called.
    - `without access: requests, then writes when granted` / `→ WeightDenied when still denied, no write`.
    - `writer HealthWriteDenied → WeightDenied`; `HealthWriteFailed/Unavailable → WeightSaveFailed`, no refresh.
    - `account changes during the access prompt → WeightSaveFailed, no write` (owner id flipped inside `requestAccess`).
    - `undo deletes once and refreshes`; `a second undo of the same SavedWeight does nothing and returns true`; `undo returns false when delete fails`.
    - `undo still works after the widget that saved it is gone` (call `undo` after disposing a listener on the provider; `weightLoggerProvider` is not autoDispose).
- [ ] **Step 2: Run** `flutter test test/health/weight_entry_test.dart test/health/weight_logger_test.dart` — expect FAIL.
- [ ] **Step 3: Implement.** `parseWeightKg`: trim, replace one `,` with `.`, match `^\d+(\.\d+)?$`, round to one decimal, range-check. `WeightLogger.save`: read owner id first; parse; `hasWriteAccess()` else `requestAccess()` then `hasWriteAccess()` again; re-check owner id; `write(kg, wallClock())`; on `HealthWeightWriteOk` refresh overview and return `WeightSaved(SavedWeight(...))`. Keep a `Set<String>` of undone client ids in memory for the double-undo rule.
- [ ] **Step 4: Run** the same command — expect PASS.
- [ ] **Step 5: Commit** `feat(health): validate and log a weight, with undo`.

### Task 3: Log weight sheet and buttons

**Files:**
- Create: `apps/mobile/lib/features/health/widgets/log_weight_sheet.dart`
- Modify: `apps/mobile/lib/features/health/widgets/body_card.dart` (new `onLogWeight` param; a kit text button `Log weight` at the bottom of every state, data and gap)
- Modify: `apps/mobile/lib/features/health/health_page.dart:193` (pass `onLogWeight: () => showLogWeightSheet(context, ref)`)
- Modify: `apps/mobile/lib/features/health/detail/body_detail_page.dart` (a `Log weight` button in the Weight panel and in the gap panel)
- Test: `apps/mobile/test/health/log_weight_sheet_test.dart`; extend `test/health/health_cards_test.dart` and `test/health/detail_pages_test.dart`

**Interfaces:**
- Consumes: Task 2's `weightLoggerProvider`, `WeightSaveResult` subclasses, `parseWeightKg`; latest weight from `healthOverviewProvider` (`BodyOverview.weight?.value`).
- Produces: `Future<void> showLogWeightSheet(BuildContext context, WidgetRef ref)`.

- [ ] **Step 1: Write failing widget tests** (override `healthWeightWriterProvider` with the fake):
  - `sheet opens prefilled with the latest weight as 72.4` and with an empty field when there is none.
  - `Save with 72.4 writes once, closes the sheet and shows "Saved to Apple Health" with Undo`; Android fake shows `Saved to Health Connect`.
  - `double-tap Save writes once` (Save disabled while saving).
  - `out-of-range shows "Enter a weight between 20 and 400 kg" under the field and does not write`.
  - `denied keeps the sheet open with "Allow BeyondRep to write weight in Settings" and Open Settings calls openSettings`.
  - `failed write shows "Couldn't save to Apple Health. Try again." and keeps the sheet open`.
  - `tapping Undo deletes the entry`; `failed undo shows "Couldn't remove it. Delete it in the Health app."`.
  - `BodyCard shows Log weight in the data state and in a gap state`; `BodyDetailPage shows Log weight` in both.
  - Text scale 2.0 and dark theme: sheet renders without overflow.
- [ ] **Step 2: Run** `flutter test test/health/log_weight_sheet_test.dart test/health/health_cards_test.dart test/health/detail_pages_test.dart` — expect FAIL.
- [ ] **Step 3: Implement.** Sheet via `showNsSheet(heightFactor: 0.5)`, `NsTextField(label: 'Weight (kg)', keyboardType: TextInputType.numberWithOptions(decimal: true), autofocus: true)`. The success snackbar is shown on the page's `ScaffoldMessenger` captured before the sheet opens, so it survives the sheet closing.
- [ ] **Step 4: Run** the same command, then `flutter test test/design_kit_guard_test.dart` — expect PASS.
- [ ] **Step 5: Commit** `feat(health): Log weight sheet on the Body card and detail page`.

### Task 4: Permissions, ADR and docs

**Files:**
- Modify: `apps/mobile/ios/Runner/Info.plist` — `NSHealthUpdateUsageDescription` = `BeyondRep writes the workouts you finish on this phone when you turn on saving in the Health tab, and the weights you log, to Apple Health.`
- Modify: `apps/mobile/android/app/src/main/AndroidManifest.xml` — add `<uses-permission android:name="android.permission.health.WRITE_WEIGHT" />` after `READ_WEIGHT`.
- Modify: `tool/test_ios_privacy_strings.py` — assert the update string contains `weight`; add (or extend the existing Android manifest test in `tool/`) an assertion that `WRITE_WEIGHT` is declared and no other new `WRITE_*` permission is.
- Create: `docs/adr/0016-log-weight-to-health-platforms.md` (Status Accepted 2026-11-28, implemented in source, not released or device-verified; decisions = the spec's section 5; consequences: no storage, Play Health apps declaration must list `WRITE_WEIGHT`, App Privacy answers unchanged as nothing is collected).
- Modify: `docs/HEALTH_DATA.md`, `docs/PRIVACY_POLICY_INPUTS.md` (permissions row), `docs/RELEASE.md` (new "Log weight device QA" table: iOS and Android first-save prompt, deny then Settings, save shows in Health app, Undo removes it, VoiceOver/TalkBack on the sheet — all `not run`), `docs/ROADMAP.md` (one line under Phase 5), `CLAUDE.md` project state (one bullet), `apps/website/src/pages/privacy.astro` (replace "It does not write or change anything in Apple Health or Health Connect." with a sentence that it writes only the workouts you choose to save and the weights you log, and never changes anything else).

- [ ] **Step 1: Write the failing tool assertions**, run `python3 -m unittest tool.test_ios_privacy_strings` — expect FAIL.
- [ ] **Step 2: Edit** Info.plist and the manifest; rerun — expect PASS.
- [ ] **Step 3: Write** the ADR and doc edits.
- [ ] **Step 4: Run** `python3 -m unittest discover -s tool -p 'test_*.py'` and `cd apps/website && npm ci && npm test && npm run build && npm run check-links` — expect PASS.
- [ ] **Step 5: Commit** `docs(health): ADR-0016 log weight; WRITE_WEIGHT and HealthKit share text`.

### Final

- [ ] From `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, full `flutter test`. Record counts.
- [ ] Opus review of the whole branch (requesting-code-review), fix findings, open the PR with the review checklist from AGENTS.md; device checks listed as not run.
