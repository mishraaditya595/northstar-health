# ObjectBox — durable local workout store

**Decision:** ObjectBox on phones/tablets; accepted in [ADR-0003](adr/0003-data-cloud-health.md). The native Store, seven initial entities and repository boundary were introduced
in PR #5. PR #7 added the exercise catalog and transactional plan builder.
**Today/Progress still show fictional demo data** and the live workout logger
is not implemented. ObjectBox cloud Sync is not used.

## Data classification and lifetime

| Entity | Lifetime | Cloud backup? |
| --- | --- | --- |
| `WorkoutSession` / `WorkoutExercise` / `WorkoutSet` | Durable until user deletes | **Completed NorthStar workouts** only, as portable snapshots |
| `WorkoutSessionState` | Durable checkpoint until finished/recovered | No; cross-phone draft restore deferred |
| `WorkoutPlan` / `PlanExercise` / `ExerciseDefinition` | Durable local, owner-scoped | **Not in MVP**; embed names in backed-up historical logs |
| `SyncOutbox`, `CloudSyncCursor`, `InboxReceipt` | Until durable ACK and retention policy | Metadata only on device |
| `HealthExportReceipt` | As long as corresponding workout relevant | Local platform-record references only |
| `HealthCache` | Expiring, permission-scoped summaries | **Never** |
| `HealthQueryCheckpoint` | Per-device until invalidated | **Never** |

Don't create an unbounded permanent `HealthObservation` archive from platform measurements. Keep short-lived bounded chart samples only when an authorized view needs them. Health caches and platform checkpoints must be purged on permission revocation and profile changes.

## Implemented phone repositories

- `ObjectBoxWorkoutRepository`
  (`apps/mobile/lib/features/workouts/data/objectbox_workout_repository.dart`):
  session creation, atomic set/save+checkpoint commits, exact retry and
  optimistic session revision guard.
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
- Migrate type changes with versioned properties and explicit data transformation; don't assume automatic conversion or database-file encryption.

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

An offline guest can save without creating a cloud operation for a stranger's account. Linking guests to a signed-in account is explicit. A server ACK (not just HTTP request completion) lets the coordinator advance a revision / compact outbox. Watch-origin events first require the phone's own durable receipt before it acknowledges the watch.

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
