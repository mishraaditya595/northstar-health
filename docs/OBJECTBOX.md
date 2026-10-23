# ObjectBox — durable local workout store

**Decision:** ObjectBox on phones/tablets; accepted in [ADR-0003](adr/0003-data-cloud-health.md). ObjectBox packages and generator are in `pubspec.yaml`, **but no Store/entities are implemented yet**. The app currently shows fictional data. ObjectBox cloud Sync is not used.

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

Initialize a single mobile `Store` when implemented, inject repositories through Riverpod and shut down cleanly. Offload large imports/aggregation with suitable ObjectBox async/isolate patterns. Profile on low-memory Android, bounded cache sizes and migration of older DB files.

ObjectBox's native file format is not proof of at-rest app-level encryption. Review OS file protection, Android/iOS backup inclusion, credentials in separate platform-secure storage, account scoping, free-text workout notes and restore/delete. Do not copy ObjectiveBox files to Supabase.

## Generator commands (once entities exist)

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format lib test
flutter analyze
flutter test
```

The build must verify generator output and model JSON changes. Never auto-delete a conflicted model UID file to make CI green.

## Review/acceptance

Offline creation, mid-session crash recovery, atomic set + outbox write, schema rename/type migration, duplicate operation replay, account switch with unsynced edits, cache expiry and permission revocation, cloud restore without custom plans, export receipt crash recovery, entry-level device profiling. Separate watch storage must be native/verified; do **not** assume mobile ObjectBox works in FlutterWatch.

References: https://docs.objectbox.io/advanced/data-model-updates and https://docs.objectbox.io/advanced/meta-model-ids-and-uids
