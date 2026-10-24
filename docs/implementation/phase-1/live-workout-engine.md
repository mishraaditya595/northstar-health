# Phase 1 — PR 3: Atomic local live-workout engine

**Scope:** Storage/domain engine only. The active workout UI, rest timer,
history, trends, watch capture and cloud backup belong to later PRs.
Code is on `feat/phase1-live-workout-engine`, branched from verified main
at `bf392d6c1cec6d0c075445dc66a43a915c43f11c`.

## Single owner, same model

`LiveWorkoutEngine` is a Riverpod-injectable domain boundary backed by
`ObjectBoxLiveWorkoutEngine` in the **single existing ObjectBox Store**.
`ObjectBoxWorkoutRepository` remains responsible for atomic, revision-safe
individual set edits. There are **no entity or ObjectBox UID changes**.

**Source of truth:** local ObjectBox only. A user can create and recover
workouts without internet, login, HealthKit, Health Connect or Firebase.
`SyncOutbox` is not used in offline guest-only Phase 1 (see foundation notes).

## Commands and invariants

- **Quick start:** explicitly named empty workout; caller supplies a
  persistent session UUID, UTC start time and original timezone offset.
- **Plan start:** read the current non-archived plan and its exercise
  definitions within one write transaction; save the new session, *copied*
  immutable exercise labels/equipment/muscle, distinct session-exercise
  UUIDs, prescribed **planned** set rows with **null** performance values,
  and the initial revision-1 recovery checkpoint. Missing plan/definition,
  malformed positions, invalid set counts or unique-ID collision aborts the
  entire transaction, leaving no partial session.
- **One unfinished workout** (in-progress or paused) per local Store:
  enforced inside the start transaction, including the legacy create path.
  Unknown status values block starting another workout; never silently
  assume a future status means completed.
- **Retries:** exact start UUID/time/source/offset replay returns the existing
  saved session, without duplicating sets or reopening completed sessions.
  Conflicting UUID reuse throws.
- **Recovery:** after a fresh process starts, look up the one unfinished
  session and its checkpoint. Missing checkpoint, unknown status or multiple
  active sessions fails closed. Individual set changes already persist their
  checkpoint and revision atomically in the existing repository.
- **State changes:** `inProgress → paused → inProgress`, or either active
  state to `completed`/`discarded`. Require `expectedRevision`; updates
  to session, checkpoint revision or checkpoint deletion are atomic. An exact
  repeated acknowledged transition with immediately previous revision is
  idempotent; late/conflicting transitions fail.
- **Finish** stores its provided UTC completion timestamp and removes the
  active checkpoint. **Discard** leaves an audit-only discarded session and
  removes the checkpoint. Later history views must show **completed only**.

## Tests on native ObjectBox

`apps/mobile/test/workouts/objectbox_live_workout_engine_test.dart`
creates disposable Store directories and verifies:

1. Atomic plan materialization, snapshots, exact start replay and null planned sets.
2. Single active workout, including legacy creation and paused state.
3. Close/reopen of native Store with committed reps/load/RPE, revision and selected-set checkpoint.
4. Pause/resume, optimistic stale command rejection and idempotency.
5. Finish/discard, state integrity and allowing a subsequent workout.
6. Plan rename/archive preserving historical session snapshots.
7. Unique generated child-ID collision aborting all writes.
8. Bad or missing plan, invalid quick start, missing checkpoint, unknown
   future status and conflicting session UUID are all fail-closed.

## Known limits and next milestone

- No in-app screen yet starts, pauses or finishes a session; **do not label
  this milestone as a usable live workout recorder**.
- Rest-timer deadlines and paused timer state exist in the v1 checkpoint
  model but **timer behavior is deferred to the active workout UI PR**.
- Only real process termination on Android/iOS validates actual OS-lifecycle
  recovery; closing/reopening a native test Store is supporting evidence,
  **not** a physical-device process-death test.
- UI in PR 4 must reload the aggregate after an optimistic conflict rather
  than retrying a stale edit with a newer revision automatically.
- Real Android/iOS, low-storage, OS backup, tablet, 2× text scale,
  accessibility and performance QA remain release gates. `main` must not
  be updated without explicit owner merge approval.
