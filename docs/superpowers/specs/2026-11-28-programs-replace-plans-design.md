# Programs replace plans: design

Date: 2026-11-28. Owner: Adi. Status: draft for owner review.

## Intent and why

The Train tab offers "plans" (one reusable workout) next to "programs" (a weekly schedule of workouts). Adi finds the two words confusing. The Train tab should offer two ways to train and nothing else:

1. **Quick workout**: an empty session, exactly as today.
2. **Programs**: pick one of the ready-made catalogue programs, or **create your own**.

Adi also decided (2026-11-28) that the user's programs, including custom ones, are **backed up to the cloud** and come back on a new phone. Today only completed workouts are backed up.

The reusable single workout is not unwanted, only its name and its place. It lives on inside programs, where the user sees it as a "workout" on a day.

## Goals

- No user-visible "plan" or "My Plans" anywhere on the phone or either watch.
- Create a custom program: name it, choose which of the seven days are training days, and give each training day a workout.
- A program's workouts can be built from scratch with the existing editor, or copied from a ready-made catalogue workout, or copied from one of the user's old saved plans.
- Every non-archived program the user has (custom or added from the catalogue, with their edits) is backed up and restored, with the same safety rules as workouts: retry with the same operation ID, server compare-and-set on revision, no silent overwrite, deletions remembered.
- The watches keep working with no contract change.

## Non-goals

- No change to Quick workout, the active workout logger, history or progress.
- No multi-week programs. A program stays one repeating seven-day week.
- No backup of in-progress sessions, custom exercises on their own, catalogue content, preferences or health data. Custom exercises travel only as snapshots inside a program that uses them.
- No program sharing between accounts.
- No change to `contracts/workout_sync/*` or `contracts/watch_link/v1`.

## Anti-goals (a failure even if it works)

- A program edit on one phone silently erasing an edit made on another.
- A restore that creates duplicate programs or resurrects a deleted one.
- Losing a user's existing saved plans without a way to reuse them.
- Any health value reaching the program backup.

## Constraints

- Backup scope change: needs **ADR-0017** (new, numbered) and edits to the "Data ownership hard rules" in `AGENTS.md`, `docs/CLOUD_SYNC.md`, `docs/SYNC_PROTOCOL.md`, `docs/ARCHITECTURE.md`, and the website's draft account-deletion page (it says plans are erased and cannot be recovered) and privacy page (`privacy.astro` lists plans under "never backed up"). These are owner-approved by this design.
- Durable write contract (AGENTS.md): the local program edit and its outbox entry commit in one ObjectBox transaction; saved only after local commit; durable receipt before dequeue.
- ObjectBox stable model UIDs; new entities only add to the model; commit generated code and `objectbox-model.json`.
- Shared component kit only (`docs/DESIGN_SYSTEM.md`), light/dark, tablet two-column (`lib/core/design/layout.dart`), text scaling.
- Supabase is development-only; migrations deploy through the manual Codemagic `supabase-database` job.
- PR #108 (Wear OS stage 3) is open and touches watch workout start. This work edits only the Wear `TrainScreen`/`PlanPreviewScreen` strings, in stage 1, and rebases on whatever merges first.

## Approaches considered (backup)

1. **One versioned record per program (chosen by Adi).** The whole program (name, description, source, start weekday, seven days, every workout with exercises and prescriptions) is one JSON aggregate, uploaded through a new RPC that copies the `sync_workout` pattern: operation UUID replay with request hash receipts, expected-revision compare-and-set, sticky tombstones, an owner-scoped change feed for restore. Proven code to copy; conflicts are detected per program.
2. Simple overwrite table with RLS upsert. Least code, but last write wins across devices, which the repo forbids. Rejected.
3. Store programs in `workout_records` with a kind column. Saves a table but mixes validation and server progress maths for two different things. Rejected.

## Design

The work ships in **two stages, two PRs**. Stage 1 is useful alone.

### Stage 1: Train tab and custom programs (phone and watches, no backend)

**Train tab** (`apps/mobile/lib/features/train/train_page.dart`):

```
Train
[ Today in Push Pull Legs  · Start ]   or   [ Quick workout ]
Your program        Push Pull Legs  >          (when one is active)
Programs            Ready-made and your own  >
Workouts            Ready-made sessions to start  >
Exercise library    >
```

- Removed: "Create training plan", the "Your plans" section and its empty state, and the "Better fit today" card that suggests one of the user's plans. "Better fit today" and per-plan recovery lines move to the active program's workouts on the Your program page (same `planFitProvider` logic, fed with the active program's workouts). This keeps stage 3 health insights alive.
- **Today** (`today_page.dart` `_Hero`, `today_overview.dart` `nextPlan`): with an active program it shows today's program workout or rest day, as now. Without one, the saved-plan suggestion is removed and the empty state reads "No program yet" with "Pick a program" (to `/train/programs`) and Quick workout. `nextPlan` and its start path for saved plans are removed.
- **Better fit today** on Your program: starting a suggested workout counts as today's program session (a swap: `programDayLocalDate` is today, so today shows done). `startProgramDay` gains an explicit "swap" entry that accepts any workout the program owns for today instead of throwing `ProgramDayChanged`. `planFitProvider` gets the active program's workouts from `ProgramRepository.programPlans`, since `listPlans()` excludes program-owned workouts.
- The quick-start card copy changes from "...or build a plan." to "...or follow a program."
- Workouts (catalogue templates) stays a browse-and-start library. Its "Copy to My Plans" button is removed; copying a template happens from the program builder instead.

**Programs page** (`/train/programs`): a "Create program" button at the top, then "Your programs" (every non-archived program, active one tagged), then the catalogue list as today. Catalogue programs open their detail page and "Add" as today.

**Create program** (new route `/train/programs/new`, one page, kit components only):

- Name (required, 1 to 100 chars, the existing limit), optional description up to 1000.
- Seven rows, Day 1 to Day 7, each "Rest" by default. Tapping a row opens a bottom sheet: "Rest day", "New workout", "Copy a ready-made workout", "Copy one of my saved workouts" (only shown when old saved plans exist), and the workouts this program already has (a workout can be on several days, as catalogue programs already allow).
- Start day (weekday of Day 1), default today's weekday, via the existing `program_weekday_sheet.dart`.
- "Make this my active program" switch, on by default.
- Save creates the program, its seven days and the program-owned workouts in one transaction, idempotent by a request UUID (same pattern as `importProgram`). At least one training day is required.
- "New workout" opens the existing plan editor (`plan_editor_page.dart`, retitled "Workout") in a mode that returns the drafted workout to the builder instead of saving a standalone plan.

**Your program page** (`my_program_page.dart`) gains: rename and edit description (custom and catalogue-added alike), "New workout" and "Copy a ready-made workout" in the day sheet next to the program's existing workouts. `ProgramRepository` gains `createProgram`, `updateDetails`, `addWorkout` (creates a program-owned workout from a draft, a template or an old plan). `setDayPlan` keeps rejecting workouts the program does not own.

**Existing saved plans**: kept in ObjectBox untouched, no data migration, never shown as a list. They only appear as copy sources in "Copy one of my saved workouts". Copying makes a program-owned duplicate. Starting a saved plan directly is no longer possible from the phone.

**Limits** (shared by phone and server, so a saved program can always be backed up): at most 30 non-archived workouts per program (counting every workout the program owns, used by a day or not), the existing 100 exercises per workout and 1000-char notes, and a whole-program snapshot of at most 512 KiB as encoded by the stage 2 payload builder. Stage 1 enforces the 30-workout limit in the builder and day sheet. Stage 2 checks the snapshot size inside the same write transaction and refuses the save with "This program is too big to back up. Remove some notes or exercises." so no program is ever stuck in the outbox.

**Wording sweep**: user-visible "plan" becomes "workout" or "program" across the phone (editor title, snackbars, errors such as "Check the plan and any unfinished workout", Today, Account & sync, the template page). Code identifiers stay (`WorkoutPlanRecord`, `planUuid`, routes may stay). A test greps user-visible strings in `lib/features/train/` and `lib/features/today/` for "plan" (case-insensitive, whole word) and fails on any hit.

**Watches**: the phone's `plans_snapshot` (`watch_snapshots.dart`) changes what it sends, not its shape: today's program workout first (as now), then the active program's other workouts, ordered by day. User plans are no longer sent. Without an active program, only the today slot is empty and the watch shows Quick workout. The phone's fallback workout name in `_planJson` changes from 'Plan' to 'Workout'. Watch strings change: Apple Watch `TrainPage` and `PlanPreviewView` ("This plan is not on your watch yet.") and Wear `TrainScreen` / `PlanPreviewScreen` become "No program yet. Pick one in BeyondRep on your iPhone/phone." and "This workout is not on your watch yet." `plan_id` and every message field keep their names.

### Stage 2: program backup and restore

**ADR-0017 "Back up training programs"** records: what is backed up (every non-archived program the user has, with its workouts, prescriptions and exercise snapshots), what is not (sessions, which program days were done or missed, which stay local; health data; catalogue content), retention (until deleted or account deletion, tombstones for the account lifetime, 90-day hash receipts, same as workouts), and that account deletion cascades.

**Server** (`supabase/migrations/2026112x_program_backup.sql`, pgTAP in `supabase/tests/program_sync.test.sql`):

- `public.program_records(user_id, program_id, payload jsonb, server_revision, server_change_seq, deleted_at, ...)`, primary key `(user_id, program_id)`, FK to `auth.users` on delete cascade, RLS owner-only SELECT, no direct writes.
- `public.program_sync_operations` receipts (hash only, 90-day expiry), pruned by the existing daily job or a sibling job.
- A separate per-owner change counter for programs, so the workout feed and its cursors are untouched.
- `public.sync_program(operation_id, program_id, expected_revision, action, payload)` and `public.get_program_changes(p_after_seq, p_limit, p_cursor_epoch)`, the same SECURITY INVOKER wrapper plus private SECURITY DEFINER shape, `auth.uid()` identity, validation before lock, same response keys as `sync_workout`.
- Payload `schema_version: 1`, strict: program fields (name up to 100, description up to 1000, source id and release, first weekday); exactly 7 days with `day_index` 0-6 and nullable `workout_id`; at most 30 workouts, 100 exercises each; **every exercise carries a full snapshot** (exercise UUID, name, muscle group, equipment, movement category, input mode, primary and secondary muscles, built-in flag) so restore never depends on the catalogue file being present; prescription bounds as in `PlanExerciseRecord.validate()` (sets 1-30, reps 1-1000 with max >= min, duration 1-3600 never with reps, rest 0-3600, notes up to 1000). Additional fields rejected, 512 KiB cap. Every day's `workout_id` must exist in the payload.
- Which program is **active**, and when it was activated, stay on each phone and are not in the payload. Activating or switching programs writes nothing to the outbox, so switching on two phones never conflicts.

**Phone**:

- New `ProgramSyncOutboxEntity` and `ProgramRemoteStateEntity` (and a program restore cursor), separate from the workout outbox so workout sync behaviour cannot change. Every program content write in `ObjectBoxProgramRepository` (create, import, edit day, add or edit a workout, rename, start day, archive; not activate) builds the full snapshot and writes the outbox entry in the same transaction. A newer snapshot supersedes a pending one that was never sent; an attempted one is retried with its own operation UUID first.
- Workout edits inside a program (plan editor saving a program-owned workout) also enqueue that program.
- Archive becomes a delete with a tombstone.
- The foreground upload coordinator and restore worker gain a program lane after workouts, sharing the session guard.
- Restore imports a program, its workouts and exercises in one transaction. An exercise snapshot whose UUID exists locally reuses the local exercise; otherwise it creates one from the snapshot (catalogue, built-in and custom alike), so repeats never duplicate. Restored programs arrive inactive; the user picks one. Programs that already exist on a phone when stage 2 ships are all uploaded. Two phones that each added the same catalogue program keep two programs (no matching by `sourceId`, since their edits may differ); this is accepted, the user can archive one.
- **Deletion wins.** A tombstone archives the local program even if this phone has an unsent edit, and the pending upload is dropped; Your programs shows "<name> was deleted on another device" once. An archive on this phone sends a delete with the expected revision; if the server revision moved, the delete is retried against the newer revision rather than turned into a conflict copy (the user asked for it gone).
- **Edit conflict** (an edit, not a delete, finds the server revision moved): the phone keeps its version as a new program named "<name> (this phone)" and imports the cloud version under the original ID, then uploads the copy as new. Nothing is lost and no review screen is needed. The user sees a one-line note on Your program.
- The cloud JSON export (#27) adds a `programs` array.
- Account & sync shows a pending program count next to workouts.

## Decided by Adi

- Remove "plans" from the Train tab; offer Quick workout and Programs with ready-made and custom programs (2026-11-28).
- Reason: the word is confusing (2026-11-28).
- Custom programs are backed up to the cloud (2026-11-28).
- Backup approach: one versioned record per program (2026-11-28).

## Calls made by Claude (for Adi to check)

- Two stages: UI first, backup second.
- Every program is backed up, not only custom ones, because a catalogue program the user edited is also theirs.
- Old saved plans: kept and offered only as copy sources, not migrated into a program.
- "Copy to My Plans" on ready-made workouts removed; Workouts stays a start-only library.
- "Better fit today" moves to Your program and suggests among the active program's workouts.
- Watch sends the active program's workouts instead of saved plans.
- Conflict handling keeps both versions instead of a review screen.
- Done and missed marks, and which program is active, are not backed up; a restored phone starts with no active program and a fresh week.
- Deletion wins over a concurrent edit.
- Full exercise snapshots in the payload; limits of 30 workouts, 100 exercises, 512 KiB, enforced on save.
- Duplicate catalogue programs from two phones are kept, not merged.
- A "Better fit today" start counts as today's program session.
- Today without an active program offers "Pick a program" and Quick workout.

## Left to the builder

- Exact sheet and editor layout within the kit, test names, file splits, the program change-counter implementation, outbox coalescing details, migration file timestamps.
