# P5-01 Save phone workouts to Apple Health / Health Connect

**Status:** implemented in source, **not released or device-verified**. Decision: [ADR-0014](../../adr/0014-save-workouts-to-health-platforms.md). Design: [spec](../../superpowers/specs/2026-11-27-phase-5-health-export-design.md). Plan: [plan](../../superpowers/plans/2026-11-27-phase-5-health-export.md). Device rows: [RELEASE.md](../../RELEASE.md).

## What exists

- **Storage:** `HealthExportSettingEntity` (the account's switch) and `HealthExportReceiptEntity` (per workout) in `lib/features/health/data/health_export_entities.dart`, with `ObjectBoxHealthExportRepository`. Generated code and `objectbox-model.json` are committed; `test/workouts/fixtures/objectbox_pre_health_export.g.dart` is the frozen pre-change model for the upgrade test.
- **Planner:** `lib/features/health/domain/workout_health_export.dart`, a pure function from workouts, receipts and watch links to write, delete, supersede and lookup actions (no ObjectBox, no Flutter). `health_export_state.dart` holds the state enum.
- **Writer:** `lib/features/health/data/health_workout_writer.dart`, `HealthWorkoutWriter` over `health` 14.0.0 (`writeWorkoutDataUUID` with `syncIdentifier`/`clientRecordId`, `deleteByUUID`/`deleteByClientRecordId`). BeyondRep's own code logs no ids, times or exception text; the plugin logs record ids (no health values) to the device log. An empty write result and a false delete are failures.
- **Exporter:** `lib/features/health/data/workout_health_exporter.dart`, one serialized pass with receipts committed before and after each platform call, `stillCurrent()` and the switch checked before every platform call, a final `deleted` receipt for deleted workouts, iOS adopt and watch-overlap checks, 50 writes per pass.
- **Controller, kicks, host:** `lib/features/health/application/workout_health_export_controller.dart` (status, `turnOn`, `turnOff`, `runPass`, `openSettings`, `healthExportKickProvider`) and `health_export_host.dart` (first frame, resume, sign-in). Kicks after a workout finishes (`active_workout_page.dart`), after a delete (`workout_history_detail_page.dart`) and after a watch import or `workout_link` (`watch_workout_inbox.dart`).
- **UI:** `lib/features/health/widgets/health_export_row.dart` on the Health tab (kit components only: a tappable `NsListCard` with an `NsTag`, `showNsSheet`, `showNsConfirm`): Off, On with saved and waiting counts, "Allow access in Settings" with an On tag that opens a sheet (Open Settings, Stop saving), first-use sheet, stop confirmation. On Android the first-use sheet leaves out the Apple Watch sentence.
- **Native declarations:** iOS `NSHealthUpdateUsageDescription` text; Android `WRITE_EXERCISE`.

## Evidence (run in the development container)

| Check | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test` | 0 changed |
| `flutter analyze` | No issues found |
| `flutter test` | 2455 passed |
| `python3 -m unittest discover -s tool -p 'test_*.py'` | 263 tests, OK (2 skipped) |

New test files: `health_export_repository_test`, `objectbox_health_export_migration_test` (old database opens, rows accepted), `domain/workout_health_export_test`, `health_workout_writer_test`, `workout_health_exporter_test`, `workout_health_export_controller_test`, `health_export_host_test`, `health_export_row_test`, plus cases in `platform_health_reader_test` (own written workout is not an outside workout), `health_page_test`, `health_import_guard_test` and `watch_workout_inbox_test`. Each was written first and seen failing before the code existed.

## Not run

- Any Xcode or Android build, and every physical-device check: the first-use permission prompt on iPhone and Android, backfill of a real history, delete removes the entry, the watch joined a phone workout (one entry), Health Connect not installed, write access revoked then app resume. Listed in [RELEASE.md](../../RELEASE.md).
- HealthKit behaviour for an equal sync version after a crash is covered by the adopt check, not by a device test.
- Supabase and pgTAP: nothing changed there.
