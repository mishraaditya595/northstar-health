# ObjectBox — durable local workout store

**Decision:** ObjectBox on phones/tablets; accepted in [ADR-0003](adr/0003-data-cloud-health.md). The native Store, seven initial entities and repository boundary were introduced
in PR #5. PR #7 added the exercise catalog and transactional plan builder.
The offline quick/plan-start and recovery engine is tracked in
[Phase 1 live workout engine](implementation/phase-1/live-workout-engine.md).
The active workout logger and persisted rest timer were merged in PR #10.
The read-only completed workout history and exercise trends are under review in
[Phase 1 PR #11](implementation/phase-1/workout-history-progress.md).
**Today health tiles still contain clearly labeled prototype data** until
Phase 3 platform permissions and measurements are implemented. ObjectBox
ObjectBox's own cloud sync is not used. P2-03 introduced the durable outbox (PR #15: **merged**), and P2-04 (PR #16: **draft**) connects it to an authenticated, foreground-only Supabase uploader.

## Data classification and lifetime

| Entity | Lifetime | Cloud backup? |
| --- | --- | --- |
| `WorkoutSession` / `WorkoutExercise` / `WorkoutSet` | Durable until user deletes | Completed NorthStar phone workouts only, after authentication; no unfinished sessions or local recovery checkpoint |
| `WorkoutSessionState` | Durable checkpoint until finished/recovered | No |
| `WorkoutPlan` / `PlanExercise` / `ExerciseDefinition` | Durable local, owner-scoped | **Not in MVP**; embed names in backed-up historical logs |
| `WorkoutSyncOutboxEntity` | Completed phone workout snapshots remain pending until matched server ACK; retain ack receipts as needed for retry and conflict | **P2-04 draft:** completed-workout DTOs are uploaded via authenticated Supabase RPC; local outbox records remain device-only |
| `HealthExportReceipt` | As long as corresponding workout relevant | Local platform-record references only |
| `HealthCache` | Expiring, permission-scoped summaries | **Never** |
| `HealthQueryCheckpoint` | Per-device until invalidated | **Never** |

Don't create an unbounded permanent `HealthObservation` archive from platform measurements. Keep short-lived bounded chart samples only when an authorized view needs them. Health caches and platform checkpoints must be purged on permission revocation and profile changes.

## Implemented phone repositories

- `ObjectBoxWorkoutRepository`
  (`apps/mobile/lib/features/workouts/data/objectbox_workout_repository.dart`):
  session creation, atomic set/save+checkpoint commits, exact retry and
  optimistic session revision guard.
- `ObjectBoxLiveWorkoutEngine`
  (`apps/mobile/lib/features/workouts/data/objectbox_live_workout_engine.dart`):
  one unfinished session; atomic plan-to-session materialization, recovery,
  checkpoint-aware optimistic lifecycle commands and no-ghost rollback.
- `ObjectBoxWorkoutLibraryRepository`
  (`apps/mobile/lib/features/workouts/data/objectbox_workout_library_repository.dart`):
  18 built-in definitions, custom exercise editing/soft archive, atomic plan
  header + child replacement, plan revision conflict handling.
- Built-in catalog identities **`builtin.v1.*` must never be renamed or
  repurposed**. They are permanent identifiers, not UI labels. Future catalog
  revisions add new IDs or explicitly migrate referents without resetting UIDs.
- An archived exercise is preserved for plans already referencing the **same
  row and exercise IDs**. It cannot be newly attached; validation is enforced
  inside the ObjectBox save transaction, not only in an editor picker.
- Plan archive requires `expectedUpdatedAtMs`; stale editors must reload,
  not silently archive a newer plan. Custom templates remain local-only.
- Implementation notes: [Phase 1](implementation/README.md) and
  [catalog/plan hardening](implementation/phase-1/plan-editor-hardening.md).

## Entity-model rules

- Every domain session, exercise, set, sync operation and receipt gets a **stable UUID**, distinct from ObjectBox `@Id` internal numeric IDs.
- Persist UTC event time plus originating timezone/offset for daily-boundary interpretation. Preserve original units for display; use canonical physical units for calculation with conversion tests.
- Store source/owner, revision, deletion state and explicit app/watch/platform origin. Historical exercise names/types are **snapshots**, not lookups that break when a user renames or deletes an exercise definition.
- Commit `lib/objectbox-model.json` and generated `lib/objectbox.g.dart` together. **Never reset entity/property UIDs on rename**; independently review schema diffs and old-version fixture upgrade tests.
- **PR #11 index-upgrade regression:** the frozen, pre-index generated model in
  `apps/mobile/test/progress/fixtures/objectbox_pre_status_index.g.dart`
  is preserved from the merged pre-PR11 model. The native test
  `apps/mobile/test/progress/objectbox_workout_history_repository_test.dart`
  creates a database with that model, closes it, then reopens it under the
  current indexed status model. It asserts that historical session, exercise,
  set and status-query data remain intact. Do not regenerate this fixture.
  Only index UID 11 was added; all existing entity/property/index UIDs are
  unchanged. CI must keep this upgrade test, not replace it with JSON-only
  comparisons or a clean-database restart test.
- Migrate type changes with versioned properties and explicit data transformation; don't assume automatic conversion or database-file encryption.

## P2-03 committed outbox boundary

The production live workout engine and legacy repository finish method call `ObjectBoxWorkoutOutbox.enqueueCompletedInTransaction` **inside** their session-completion write transaction. Only `completed` phone-authored workouts create a validated, immutable P2-01 JSON DTO and durable operation UUID. Paused, active and discarded sessions never enqueue. Invalid cloud DTOs do **not** block local completion: the same atomic transaction stores the completed workout plus a `blocked` receipt (no payload), surfaced to the user as not backed up. Database write failures still roll back. A duplicate finish does not enqueue twice. Pending queries use an indexed, bounded batch with deterministic timestamp/revision/IDs ordering before the limit instead of loading all rows. Completing a workout invalidates the cached blocked-workout count so Today immediately reflects any new blocked receipt. Per-owner physical ObjectBox partitions from P2-02 isolate pending operations. `pending()` survives process restart; `acknowledge()` requires a matching operation UUID/local revision and validated server sequence, and is used by the P2-04 network worker (draft). P2-03 itself performed no HTTP requests. See [P2-03 implementation notes](implementation/phase-2/p2-03-durable-outbox.md).

## Local-first transaction

```text
set or session edit
  -> validate against domain model
  -> ObjectBox transaction:
       persist new record revision
       persist same-domain operation in SyncOutbox (if authorized/associated)
  -> UI confirms local save
  -> independent Supabase worker retries by operation UUID
```

Everyone must authenticate first (no guest mode); subsequent local logging stays available offline to a device securely bound to that account. Local workouts are never assigned to a different account. An acknowledged server write (not a sent HTTP request) permits outbox advancement. See ADR-0005. Watch-origin events first require the phone's own durable receipt before it acknowledges the watch.

## Lifetime, performance and security

A single mobile `Store` is initialized before rendering the app and repositories are injected through Riverpod. Shut down cleanly. Offload large imports/aggregation with suitable ObjectBox async/isolate patterns. Profile on low-memory Android, bounded cache sizes and migration of older DB files.

ObjectBox's native file format is not proof of at-rest app-level encryption. Review OS file protection, Android/iOS backup inclusion, credentials in separate platform-secure storage, account scoping, free-text workout notes and restore/delete. Do not copy ObjectBox database files to Supabase.

## Developer verification

```sh
flutter pub get --enforce-lockfile
# Run the generator only after a reviewed entity-model change:
# dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

The build must verify generator output and model JSON changes. Never auto-delete a conflicted model UID file to make CI green.

**Native macOS tests:** Dart/Flutter unit tests that open ObjectBox need the
matching `libobjectbox.dylib` on the host; the Flutter dependency does not
make it available automatically to standalone host unit-test processes.
On macOS, from repository root run `bash scripts/test_objectbox_macos.sh`.
The script downloads the **exact v5.3.2 universal library**, checks SHA-256,
extracts it into a temporary directory, then copies the verified
`libobjectbox.dylib` into `apps/mobile/` for the test process. The script
refuses to overwrite a pre-existing file, removes only its own copy on exit,
and the dylib path is listed in `.gitignore`. Do not rely on
`DYLD_LIBRARY_PATH`: Flutter launched through a protected macOS shell can
lose that environment variable. Linux CI similarly pins the v5.3.2 native
binary and SHA-256. These are **test-host** setup steps, not runtime
shipping or app bundle configuration. The script was independently
validated on macOS using Flutter 3.47.3; Flutter 3.47.7 remains the
repository's pinned CI version.

## Review/acceptance

Offline creation, mid-session crash recovery, atomic set + outbox write, schema rename/type migration, duplicate operation replay, account switch with unsynced edits, cache expiry and permission revocation, cloud restore without custom plans, export receipt crash recovery, entry-level device profiling. Separate watch storage must be native/verified; do **not** assume mobile ObjectBox works in FlutterWatch.

References: https://docs.objectbox.io/advanced/data-model-updates and https://docs.objectbox.io/advanced/meta-model-ids-and-uids
