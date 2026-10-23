# Phase 1 — Offline workout logger implementation

**Status:** PR1 foundation under review; not a functional workout app yet.

This milestone defines the local ObjectBox model and repository contract for
offline session recording. It intentionally does **not** integrate Supabase,
HealthKit/Health Connect, Firebase, watches or cloud operations.

## Local entities

- `ExerciseDefinitionEntity`, `WorkoutPlanEntity`, `PlanExerciseEntity`:
  local-only catalog and templates, CRUD deferred to PR2.
- `WorkoutSessionEntity`, `WorkoutExerciseEntity`, `WorkoutSetEntity`:
  stable UUIDs, immutable exercise-name snapshots, UTC timestamps and revision.
- `WorkoutSessionStateEntity`: persisted recovery/timer deadline metadata;
  actual lifecycle/timer controllers deferred to PR3–4.

Only internal ObjectBox `id` fields use numeric IDs. Domain identities use
stable UUIDs; history must not resolve labels from editable plan definitions.

## Working foundation API

`ObjectBoxWorkoutRepository` implements session create/read, add exercise,
idempotent set save, and finish. Each set save commits a set, session revision,
and checkpoint in **one ObjectBox write transaction**. Methods return only after
the local commit; they never fabricate remote backup status.

UI features currently remain demo placeholders. The application opens one
ObjectBox Store before launching the UI. Startup failure is fail-closed:
**never delete a database to make the app open**.

## Important remaining gates

- Independently verify native write rollback and reopen on Android/iOS.
- Freeze and preserve a prior-version database fixture before shipping schema
  changes; this initial PR introduces the v1 model and generated UID JSON.
- Add actual plan catalog, active workout recovery controllers and progress in
  subsequent Phase 1 PRs.
- Validate storage protection/backup policies on both mobile platforms.

From `apps/mobile` run:
```sh
flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

**Never delete `lib/objectbox-model.json`** when the generator requests a UID
migration. Review generated changes, include both `lib/objectbox.g.dart` and
`lib/objectbox-model.json` in the same PR, and test old-to-new DB compatibility.
