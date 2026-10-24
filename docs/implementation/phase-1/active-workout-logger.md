# Phase 1 — PR #10: Offline active-workout logger and rest timer

**Base:** latest reviewed `main` at `a9821633a77a2770510e4de3ec91b497d960dc44`
(merged engine PR #9). **No schema/model-UID changes.**

## User experience

- Train: start an empty named workout or begin a saved training plan.
  An unfinished session surfaces as a resumable card, including after app
  process death and reopening ObjectBox. Only one unfinished workout is allowed.
- Active workout: show historical exercise snapshots and ordered sets, add
  exercises from the local catalog and add sets, record or edit reps,
  optional load, kg/lb display unit, warm-up/working set kind and optional
  RPE; skip planned sets. Completed sets cannot be skipped accidentally.
  Other rows retain unsaved input after a set is saved, and load values
  round-trip exact integer grams.
  Display completed set count and durable local-save status.
- Pause/resume/finish/discard call `LiveWorkoutEngine` with the observed
  session revision. Destructive completion/discard requires user confirmation.
  Errors leave the session untouched; stale revisions demand explicit reload
  rather than silent retries.
- Rest: each completed set can *atomically* start an optional countdown
  (60/90/120 seconds, default 90) with the local set write. A separate
  rest-card control can restart or clear the timer. **The UTC deadline is
  persisted**, not a UI tick counter. Pausing freezes remaining time;
  resuming recreates the deadline. Updating a completed set does not restart
  its rest countdown. Backgrounding/reopening the app does not reset
  countdown duration. Replacing the persisted deadline during an ongoing
  countdown updates the display and ticker without referencing an expired
  previous deadline.
- Workouts and timer checkpoints are **ObjectBox-local**. No account,
  internet, HealthKit/Health Connect, Firebase collection, watch recording or
  cloud backup is introduced. Prescribed plan targets are not inferred
  as performed reps/load. Local-only history cannot survive reinstall unless
  a future opt-in backup mechanism is implemented.

## Storage / consistency

- Reuses `WorkoutSession`, `WorkoutExercise`, `WorkoutSet` and
  `WorkoutSessionState` already committed in PR #5.
- `WorkoutRepository.saveSet(restSeconds: ...)` commits set content,
  session revision, checkpoint and rest deadline **in one ObjectBox write
  transaction**. A failed write must not show a saved value or start rest.
- Timer-only changes use the checkpoint's monotonic `savedAtMs` token
  plus session revision inside a write transaction. A delayed clear cannot
  cancel a newer timer. Neither timer-only operation increments session
  revision, so it cannot silently invalidate a prepared set update.
- `LiveWorkoutEngine.pauseWorkout/resumeWorkout` freezes/restores running
  rest time inside their session write transaction; stale session revisions
  still conflict. Finishing/discarding deletes the checkpoint.
- The UI reads Riverpod `activeWorkoutProvider` and `WorkoutActions`
  instead of directly opening ObjectBox boxes or using a network SDK.
  Invalid/unknown persistent statuses fail closed; no automatic DB reset.

## Evidence and release gates

- Native ObjectBox tests: complete a set + rest atomically and reopen Store,
  freeze/resume countdown, stale timer clear prevention, illegal timer
  transitions after completion.
- UI/native smoke: quick start -> add exercise -> add set -> log load/RPE ->
  pause/resume -> finish; close/reopen DB and resume unfinished workout.
- Review format, analyzer, Flutter/widget/native tests, Android debug and
  Wear OS debug quality gates; do not claim actual device execution without
  separate evidence.
- **Still required for Phase 1:** completed history and progress screens;
  genuine Android/iOS force-stop, airplane-mode and low-storage tests;
  iOS build/archive, backup-exclusion audit, phone/tablet, dark/light,
  2× text-scale and accessibility QA; Codemagic integration validation.
- PR #10 is review-only. **Never merge without explicit owner approval.**

## Known scope limits

- Default per-set rest selection is not automatically populated from
  `PlanExercise.restSeconds`; prescriptions are not yet part of immutable
  workout session snapshots. This PR explicitly uses user-selectable
  seconds rather than silently assuming a plan's targets were followed.
- No workout notes, supersets, plates, PR calculation or aggregate history UI.
- Rest display uses a typed, fail-closed status decoder. Idle timers do not run
  a background one-second ticker. Timer-only state remains in ObjectBox.
- Timer is a visual countdown; notification/haptic cues are deferred until
  native app background/permission behavior is tested on real devices.
- Edits typed but not explicitly saved are not durable; after an optimistic
  conflict, the user must reload and deliberately re-enter/reconcile edits.
- A corrupted/unsupported persisted rest state fails closed at checkpoint
  recovery. The workout remains in ObjectBox but the screen cannot be used
  until a future supervised repair or recovery UI is implemented. Phase 1
  intentionally does **not** offer automatic repair, reset or discard through
  that error state; this requires a separate scoped, audited recovery plan.
