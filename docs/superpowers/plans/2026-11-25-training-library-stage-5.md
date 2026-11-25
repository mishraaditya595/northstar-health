# Training library stage 5: exercise content, implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The catalogue grows from 18 to about 230 exercises across barbell, dumbbell, machine, cable, bodyweight, band, kettlebell and small equipment. All text is original, muscles are accurate, and every exercise is loggable today. The picker and the Exercises page get filters and stay fast with that many entries. Release 2 is generated as a migration so that merging and running the database job publishes it.

**Architecture:** This stage changes content and UI only. There is no schema, server or sync change. New JSON source files are added under `catalog/exercises/`, one per equipment family, and tightened Python content tests guard them. The phone side keeps the existing parser and repository: `ExerciseChoice` gains the fields filters need, and the two lists switch to lazy builders. The last task runs the existing `catalog_build.py publish`.

**Tech Stack:** JSON plus the Python validator and build (`scripts/`, `tool/`), Flutter 3.47.7, Riverpod 3.

**Spec:** `docs/superpowers/specs/2026-11-25-training-library-design.md` sections 4.1 to 4.4, 5.3, 7, and 8 (stage 5). Also read `docs/CATALOG.md` and `catalog/PROVENANCE.md`. Executors read them.

## Decisions this plan makes

- **Only loggable modes.**
  - Rep exercises use `reps_load`, including bodyweight ones, where load is optional added weight, as for the existing push-up.
  - Holds use `duration`.
  - No `reps` or `duration_load` exercises are added (no carries yet): a mode is fixed per ID forever, and the app cannot log those two modes.
  - Carries and bodyweight `reps` come with the stage that makes them loggable.
- **Coverage target: about 210 new exercises.** Barbell ~30, dumbbell ~45, machine ~30, cable ~30, bodyweight ~35 (8 or more of them holds in `duration`), band ~15, kettlebell ~15, and EZ bar, trap bar, plate, box and rings together ~10.
  - Categories `mobility` and `conditioning` are left out. Their reps or seconds are not meaningful training data for recovery.
  - Exact counts may differ by ±20%. Coverage of every muscle matters more: each of the 14 muscles must be the primary muscle of at least 5 exercises.
- **Writing rules for every exercise:**
  - 2 to 4 cues, in plain imperative English, without a trailing full stop.
  - Each cue covers setup, the movement or a safety point.
  - No outcome or medical claims ("builds", "burns", "fixes", "prevents injury").
  - 1 to 3 primary muscles. Secondary muscles are only real assisting muscles.
  - Aliases are only other names for the same movement. A chin-up is not an alias of a pull-up.
- **Names follow the existing style:** "Equipment + movement", for example "Dumbbell bench press" and "Cable lateral raise". Names are unique ignoring case, and no alias equals another exercise's name.
- **Muscle group** is the coarse group a lifter would file the exercise under: Chest, Back, Legs, Shoulders, Arms or Core.
- **The 18 existing exercises are unchanged** (`legacy.json` is not edited). Their IDs, names and modes are locked, and the content test already pins them.
- **Owner review is the release gate.** Merging the PR and running the `supabase-database` job is what publishes release 2. After the agent finishes, a readable review sheet (one table per file) is generated for the owner outside the repo, and nothing is merged until the owner has read it. Rollback, if a release turns out wrong: `catalog_build.py rollback --to 1`.
- **Filters:** muscle group chips (All, Chest, Back, Legs, Shoulders, Arms, Core) and an equipment dropdown (All plus the equipment present in the current list). They appear on both the Exercises page and the picker sheet, and combine with search. Search also matches the display names of primary muscles, so "hamstrings" finds RDLs. Both lists use lazy `ListView.builder`/`SliverList` rows.
- **No snapshot schema bump.** The changes are additive content only, so `minAppCatalogSchema` stays 1.

## Running checks

From the repo root, run `python3 -m unittest discover -s tool -p 'test_*.py'` and `python3 scripts/catalog_build.py check`. From `apps/mobile/`, run `dart format --output=none --set-exit-if-changed lib test`, then `flutter analyze`, then `flutter test`. Flutter is at `/opt/sdk/flutter/bin` if it is not on PATH.

## Global Constraints

- IDs: `builtin.v1.<slug>`, with the slug in lowercase-hyphen form. Never reuse an ID from `catalog/releases.lock.json`.
- Vocabularies are exactly those in `catalog/schema/catalog.schema.json`: muscle, muscleGroup, equipment and category.
- Text limits: name 80, alias 60 (up to 10), cue 160 (up to 6). Integers only, no URLs and no media keys.
- The snapshot must stay under 2 MiB of canonical bytes. Expect about 150 KB.
- Text is original writing only (PROVENANCE.md). Do not copy from any website or dataset.
- Kit components only in the UI (`NsChip`, `NsDropdown`, `NsTextField`, `NsListCard`). Support light and dark, text scale 2.0 at 390 × 844, and screen-reader labels.
- Public repo: no personal data.

## Review Focus

1. **Wrong or vague muscles:** a muscle tagged primary that only stabilises, or a missing major mover, skews recovery. Content tests catch structural issues only, so the owner's review sheet is the real check (Tasks 2 to 4).
2. **Duplicate movements under two IDs** ("Dumbbell flat bench press" and "Dumbbell bench press"): the unique-name and alias tests in Task 1 must catch these. Spellings that differ but mean the same movement need a careful read.
3. **A picker with 230 rows at text scale 2.0** on a small phone: rows must not overflow, and filters plus search must not drop the custom exercises or the 18 local built-ins (Task 5).
4. **An exercise the app cannot log** (`reps` or `duration_load`) must not appear in the new files (Task 1 content test). The phone already hides such modes, but a permanent mode mistake cannot be undone.
5. **Publishing determinism:** the generated release 2 migration must match the lock and the checksum, and `legacy.json` must be byte-identical to main (Task 6).

---

### Task 1: Content guard tests

**Files:**
- Modify: `tool/test_catalog_content.py`

**Interfaces:**
- New tests over `source_exercises()`:
  - `test_new_exercises_use_loggable_modes`: every mode is in `{reps_load, duration}`.
  - `test_names_and_aliases_are_unique`: names are unique case-insensitively, aliases are unique across all exercises, and no alias equals another exercise's name.
  - `test_cue_style`: each exercise has 2 to 6 cues (legacy ones may have 1 or more), and no cue ends with "." or contains "http".
  - `test_no_outcome_claims`: no cue, name or alias contains, case-insensitively, any of `burn`, `fat loss`, `tone`, `prevent injur`, `cure`, `guarantee`.
  - `test_primary_count`: 1 to 3 primary muscles.
  - `test_every_muscle_is_well_covered`: each of the 14 muscles is primary in at least 5 active exercises. Gate this one with `skipUnless` on a total above 100 exercises, so it is green before content lands and strict after.
  - `test_legacy_file_unchanged`: the SHA-256 of `catalog/exercises/legacy.json` equals the value committed in the test, taken from main.

- [ ] **Step 1: Write the tests.** They should pass on today's 18 exercises, except any rule the legacy file breaks. Check, and exempt legacy only where needed, saying why in a comment.
- [ ] **Step 2: Run** `python3 -m unittest tool.test_catalog_content`. Expected: PASS. Then add one deliberately bad temporary entry per rule and watch each test fail. Remove the entries.
- [ ] **Step 3: Commit** `test(catalog): guard exercise content style, uniqueness and modes`

### Task 2: Free-weight exercises

**Files:**
- Create: `catalog/exercises/barbell.json` (barbell, EZ bar and trap bar), `catalog/exercises/dumbbell.json`, `catalog/exercises/kettlebell.json`

- [ ] **Step 1: Write the exercises** following the Decisions writing rules. Cover:
  - squat, hinge, lunge, horizontal and vertical push and pull for each tool;
  - isolation for arms, shoulders and calves;
  - core where it fits (for example kettlebell windmill or dumbbell side bend).
- [ ] **Step 2: Run** `python3 -m unittest tool.test_catalog_content` and `python3 scripts/catalog_build.py check`. Expected: PASS, and the check prints a size.
- [ ] **Step 3: Commit** `feat(catalog): barbell, dumbbell and kettlebell exercises`

### Task 3: Machine and cable exercises

**Files:**
- Create: `catalog/exercises/machine.json`, `catalog/exercises/cable.json`

- [ ] **Step 1: Write the exercises.** Use the generic names seen across most gyms ("Seated chest press machine", "Hack squat machine"). There is no Smith machine in the equipment vocabulary: use `machine`. Do not repeat a legacy machine or cable exercise (leg press, leg curl, leg extension, lat pulldown, seated row, triceps pushdown).
- [ ] **Step 2: Run** the same checks. Expected: PASS.
- [ ] **Step 3: Commit** `feat(catalog): machine and cable exercises`

### Task 4: Bodyweight, band and small-equipment exercises

**Files:**
- Create: `catalog/exercises/bodyweight.json` (including `pull_up_bar`, `rings`, `box` and `bench` movements), `catalog/exercises/band.json`

- [ ] **Step 1: Write the exercises.** Include at least 8 holds in `duration` mode, for example side plank, hollow body hold, wall sit, dead hang, glute bridge hold and L-sit. The `builtin.v1.plank` already exists, so don't repeat it. Add chin-up as its own exercise.
- [ ] **Step 2: Run** the same checks. `test_every_muscle_is_well_covered` now runs and must PASS. Fill any muscle below 5 with sensible additions to the files from this task or Tasks 2 and 3.
- [ ] **Step 3: Commit** `feat(catalog): bodyweight, band and holds`

### Task 5: Filters and a fast list

**Files:**
- Modify: `apps/mobile/lib/features/catalog/domain/exercise_choices.dart`, `lib/features/train/exercise_catalog_page.dart`, `lib/features/train/exercise_picker_sheet.dart`
- Create: `lib/features/catalog/domain/exercise_filter.dart`
- Test: `test/catalog/exercise_choices_test.dart`, `test/catalog/exercise_filter_test.dart` (new), `test/train/exercise_catalog_page_test.dart`, `test/train/exercise_picker_sheet_test.dart`

**Interfaces:**
- `ExerciseChoice` gains `List<String> primaryMuscles`. It is filled from the catalogue entry or the local record's `primaryMuscles`, and is empty for custom exercises.
- `matchesExerciseQuery` also matches `muscleDisplayName` of each primary muscle.
- `exercise_filter.dart` provides:
  - `class ExerciseFilter { const ExerciseFilter({this.group, this.equipment}); final String? group; final String? equipment; bool matches(ExerciseChoice c); }`. `group` compares with `c.muscleGroup` ignoring case. `equipment` is one equipment label and matches when it is one of the comma-separated labels in `c.equipment`.
  - `List<String> equipmentOptions(List<ExerciseChoice> all)`: the sorted, distinct labels.
- Both screens have a horizontally scrolling chip row for the group and an `NsDropdown` for equipment above the list. The rows render lazily. The page's "Custom only" chip stays.

- [ ] **Step 1: Write failing tests**:
  - Filter by group and by equipment, and both combined with a query.
  - "hamstrings" finds `builtin.v1.rdl` through its muscles.
  - Custom exercises still show under "All" and their own group.
  - `equipmentOptions` gives distinct, sorted labels.
  - A widget test with 250 synthetic choices: choosing the "Legs" chip and the "Dumbbell" option shows only matching rows. The first row is visible and the list is lazy (an off-screen row's text is not found before scrolling).
  - The same screen at text scale 2.0, 390 × 844, in light and dark, has no overflow.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/catalog test/train test/design_kit_guard_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(train): filter exercises by muscle group and equipment`

### Task 6: Publish release 2 and document it

**Files:**
- Generated: `supabase/migrations/<ts>_catalog_release_2.sql`, plus `catalog/releases.lock.json` and `catalog/CHANGELOG.md` (updated by the script)
- Modify: `docs/CATALOG.md` (content rules from the Decisions, and the release 2 note), `docs/ROADMAP.md` (stage 5 implemented in source, not published until the owner deploys), `docs/RELEASE.md` (device rows: the first download of release 2 on iOS and Android, picker scroll and filter at large text, offline with a cached release 1 then online)

- [ ] **Step 1: Run** `python3 scripts/catalog_build.py check`. Expected: PASS with about 230 exercises and a size well under 2 MiB.
- [ ] **Step 2: Publish.** Run `python3 scripts/catalog_build.py publish --timestamp <YYYYMMDDHHMMSS later than the newest migration, at least 20261126030000> --published-at <the same moment, RFC 3339 UTC with Z>`. Never hand-edit the output.
- [ ] **Step 3: Run** `python3 -m unittest discover -s tool -p 'test_*.py'` (PublishedReleaseTest must cover release 2), then from `apps/mobile` run `flutter test test/catalog`. Expected: PASS.
- [ ] **Step 4: Write the docs**, then run the full Running checks. Expected: all PASS.
- [ ] **Step 5: Commit** `feat(catalog): publish release 2 with the expanded exercise library`
