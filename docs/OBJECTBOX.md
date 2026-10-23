# ObjectBox — mobile persistence decision and agent contract

**Decision:** Use the **stable** ObjectBox 5.x Flutter/Dart packages for Northstar's phone/tablet durable offline data; replace all previous Drift/SQLite choices. The current app is still a mock dashboard; installing package dependencies does not mean it stores sessions yet.

## Packages and setup

`objectbox`, `objectbox_flutter_libs`, `objectbox_generator` and `build_runner` are configured in `pubspec.yaml`. Prefer release 5.3.2 (current stable as of 23 October 2026); do not upgrade to ObjectBox 6 pre-release during foundation work. Follow upstream getting-started instructions for native runners. Generator must run after first annotated entities:

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

Commit **both** generated `lib/objectbox.g.dart` and **`lib/objectbox-model.json`** along with schema changes. The JSON retains stable entity/property identifiers for safe changes; never regenerate it from scratch or overwrite IDs just to resolve conflicts.

## Entity design (proposed; do not fabricate finished schema)

- `WorkoutPlan`, `PlanExercise`: stable user-visible plan IDs, intended order and version.
- `WorkoutSession`, `PerformedSet`: immutable external UUIDs, exercise IDs, load/unit, reps, status, start/end UTC timestamps, source and local status.
- `HealthObservation`: value/unit, source app/watch, sample identity, UTC interval and last imported time; avoid duplicating existing platform aggregations.
- `OutboxEvent` and `InboxReceipt`: idempotent watch/phone cross-device commands with protocol version, event ID, per-session sequence, payload, retry/ack and reconciliation.
- `SyncCursor`, `ImportSource`: bounded incremental ingest; revoked permission state and last successful sync.

ObjectBox internal `@Id` integer is **not** the cross-device event or session identity: always use independent UUID-style IDs on events and workouts. Index lookup fields. Explicitly define relationships, unique constraints, delete semantics and UTC timestamp mapping before adding entities.

## Atomicity, performance and lifecycle

- Initialize one mobile Store when persistent features arrive; inject via Riverpod/repository abstraction; close safely on teardown. Run heavy import/index/update work with appropriate ObjectBox async/isolate APIs.
- Persist a completed set **and its outbound event in one local transaction** before showing success. Never create an event without a durable set, or mark remote delivery successful before the receiver's durable ACK.
- Offline queue must resume after process death, tolerate repeats and reconcile divergent changes. Store only necessary health samples and enforce retention/backup/export/deletion.
- Profile startup, 1,000–100,000-set queries, health imports, and watch reconnection on an entry Android device. Avoid per-frame broad queries.
- No guarantee the mobile ObjectBox native runtime works on watchOS FlutterWatch; use native watch-side persistence and versioned protocol until separately proven.

## Review gates

Exercise CRUD, process-death resume, atomic set+outbox consistency, duplicate replay, schema ID changes, fresh install/upgrades, restore/export, data deletion, permission revocation and memory/performance. Include a measured migration path for breaking schemas.

Official docs: https://docs.objectbox.io/getting-started and https://pub.dev/packages/objectbox
