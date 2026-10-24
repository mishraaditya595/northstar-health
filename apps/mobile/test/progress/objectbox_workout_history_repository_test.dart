import 'dart:io';

import 'fixtures/objectbox_pre_status_index.g.dart' as legacy;

import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/progress/data/objectbox_workout_history_repository.dart';
import 'package:northstar_health/features/progress/domain/workout_history_models.dart';
import 'package:northstar_health/features/workouts/data/objectbox_live_workout_engine.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_repository.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';
import 'package:northstar_health/objectbox.g.dart';

void main() {
  late Directory directory;
  late Store store;
  late ObjectBoxLiveWorkoutEngine engine;
  late ObjectBoxWorkoutRepository editor;
  late ObjectBoxWorkoutHistoryRepository history;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('northstar-history-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    engine = ObjectBoxLiveWorkoutEngine(store);
    editor = ObjectBoxWorkoutRepository(store);
    history = ObjectBoxWorkoutHistoryRepository(store);
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  void create(
    String id,
    DateTime start, {
    bool finish = true,
    bool discard = false,
  }) {
    engine.startWorkout(
      sessionUuid: id,
      quickName: 'Session $id',
      startedAtUtc: start,
      originalOffsetMinutes: 330,
    );
    editor.addExercise(
      WorkoutExerciseRecord(
        uuid: 'exercise-$id',
        sessionUuid: id,
        definitionUuid: 'builtin.v1.bench-press',
        nameSnapshot: 'Bench press',
        position: 0,
      ),
    );
    final current = editor.getSession(id)!;
    editor.saveSet(
      sessionUuid: id,
      expectedRevision: current.revision,
      set: WorkoutSetRecord(
        uuid: 'set-$id',
        exerciseUuid: 'exercise-$id',
        position: 0,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.completed,
        reps: 8,
        loadGrams: 62500,
        completedAtUtc: start.add(const Duration(minutes: 5)),
      ),
    );
    final updated = editor.getSession(id)!;
    if (finish) {
      engine.finishWorkout(
        id,
        expectedRevision: updated.revision,
        finishedAtUtc: start.add(const Duration(minutes: 20)),
      );
    } else if (discard) {
      engine.discardWorkout(id, expectedRevision: updated.revision);
    }
  }

  test('pre-index database upgrades and indexed history query keeps all data', () {
    // Unlike a model-only JSON assertion this creates an actual database with
    // the pre-PR11 generated bindings, closes it, then opens it with the new
    // indexed model. The fixture must remain frozen when models regenerate.
    final oldDir = Directory.systemTemp.createTempSync('northstar-v1-upgrade-');
    final begun = DateTime.utc(2026, 9, 1, 23, 40).millisecondsSinceEpoch;
    final finished = DateTime.utc(2026, 9, 2, 0, 15).millisecondsSinceEpoch;
    try {
      final before = Store(
        legacy.getObjectBoxModel(),
        directory: oldDir.path,
      );
      try {
        before.box<WorkoutSessionEntity>().put(
          WorkoutSessionEntity(
            uuid: 'legacy-session',
            name: 'Pre-index completed workout',
            status: WorkoutStatus.completed.name,
            startedAtMs: begun,
            completedAtMs: finished,
            originalOffsetMinutes: 330,
            updatedAtMs: finished,
          ),
        );
        before.box<WorkoutSessionEntity>().put(
          WorkoutSessionEntity(
            uuid: 'legacy-active',
            name: 'Not completed',
            status: WorkoutStatus.inProgress.name,
            startedAtMs: begun,
            originalOffsetMinutes: 330,
            updatedAtMs: begun,
          ),
        );
        before.box<WorkoutExerciseEntity>().put(
          WorkoutExerciseEntity(
            uuid: 'legacy-exercise',
            sessionUuid: 'legacy-session',
            definitionUuid: 'builtin.v1.bench-press',
            nameSnapshot: 'Old bench snapshot',
            equipmentSnapshot: 'Barbell',
            position: 0,
          ),
        );
        before.box<WorkoutSetEntity>().put(
          WorkoutSetEntity(
            uuid: 'legacy-set',
            exerciseUuid: 'legacy-exercise',
            position: 0,
            kind: WorkoutSetKind.working.name,
            status: WorkoutSetStatus.completed.name,
            reps: 7,
            loadGrams: 75000,
            inputUnit: 'kg',
            completedAtMs: begun + 60000,
            updatedAtMs: begun + 60000,
          ),
        );
      } finally {
        before.close();
      }

      final after = Store(getObjectBoxModel(), directory: oldDir.path);
      try {
        final migrated = ObjectBoxWorkoutHistoryRepository(after)
            .readCompleted().sessions;
        expect(migrated.map((s) => s.uuid), ['legacy-session']);
        final workout = migrated.single;
        expect(workout.name, 'Pre-index completed workout');
        expect(workout.completedAtUtc,
            DateTime.fromMillisecondsSinceEpoch(finished, isUtc: true));
        expect(workout.originalOffsetMinutes, 330);
        expect(workout.exercises.single.nameSnapshot, 'Old bench snapshot');
        expect(workout.sets.single.reps, 7);
        expect(workout.sets.single.loadGrams, 75000);
        expect(calculateWorkoutHistory(migrated).loadedVolumeGramReps, 525000);
        // A query using the newly indexed status must also exclude old
        // in-progress rows after the upgrade.
        final query = after.box<WorkoutSessionEntity>()
            .query(WorkoutSessionEntity_.status.equals('completed')).build();
        try {
          expect(query.find().map((e) => e.uuid), ['legacy-session']);
        } finally {
          query.close();
        }
        expect(after.box<WorkoutSessionEntity>().getAll(), hasLength(2));
      } finally {
        after.close();
      }
    } finally {
      oldDir.deleteSync(recursive: true);
    }
  });

  test('completed native sessions survive Store restart with actual sets', () {
    create('s1', DateTime.utc(2026, 10, 23, 8));
    var results = history.readCompleted().sessions;
    expect(results, hasLength(1));
    expect(results.single.sets.single.loadGrams, 62500);
    expect(results.single.completedAtUtc, DateTime.utc(2026, 10, 23, 8, 20));

    store.close();
    store = Store(getObjectBoxModel(), directory: directory.path);
    history = ObjectBoxWorkoutHistoryRepository(store);
    results = history.readCompleted().sessions;
    expect(results, hasLength(1));
    expect(results.single.exercises.single.nameSnapshot, 'Bench press');
    expect(calculateWorkoutHistory(results).loadedVolumeGramReps, 500000);
  });

  test('unfinished, discarded, deleted and unknown statuses never appear', () {
    create('complete', DateTime.utc(2026, 10, 21, 8));
    create(
      'discard',
      DateTime.utc(2026, 10, 22, 8),
      finish: false,
      discard: true,
    );
    create('active', DateTime.utc(2026, 10, 23, 8), finish: false);
    final original = history.readCompleted().sessions;
    expect(original.map((s) => s.uuid), ['complete']);
    final raw = store.box<WorkoutSessionEntity>();
    final complete = raw.getAll().singleWhere((e) => e.uuid == 'complete');
    // An imported platform record must not masquerade as a NorthStar log.
    complete.origin = 'health_connect_import';
    raw.put(complete);
    expect(history.readCompleted().sessions, isEmpty);
    complete.origin = 'northstar_phone';
    raw.put(complete);
    expect(history.readCompleted().sessions.map((s) => s.uuid), ['complete']);
    complete.deletedAtMs = DateTime.utc(2026, 10, 24).millisecondsSinceEpoch;
    raw.put(complete);
    expect(history.readCompleted().sessions, isEmpty);
    final active = raw.getAll().singleWhere((e) => e.uuid == 'active');
    active.status = 'unsupported_future';
    raw.put(active);
    expect(history.readCompleted().sessions, isEmpty);
  });

  test('history order uses completion time descending, not creation order', () {
    create('late', DateTime.utc(2026, 10, 24, 8));
    create('early', DateTime.utc(2026, 10, 23, 8));
    expect(history.readCompleted().sessions.map((s) => s.uuid), [
      'late',
      'early',
    ]);
  });

  test('completed record missing finish timestamp is excluded by query', () {
    create('missing-end', DateTime.utc(2026, 10, 20, 8));
    final box = store.box<WorkoutSessionEntity>();
    final row = box.getAll().single;
    row.completedAtMs = null;
    box.put(row);
    expect(history.readCompleted().sessions, isEmpty);
  });

  test(
    'worker-isolate history reads see committed sets and preserve ordering',
    () async {
      create('a', DateTime.utc(2026, 10, 20, 8));
      create('b', DateTime.utc(2026, 10, 21, 8));
      final result = await history.readCompletedAsync();
      expect(result.sessions.map((s) => s.uuid), ['b', 'a']);
      expect(
        calculateWorkoutHistory(result.sessions).loadedVolumeGramReps,
        1000000,
      );
    },
  );

  test(
    'profile 300 finished sessions with 1200 performed sets on worker',
    () async {
      // Bulk native fixture runs in one transaction to keep the benchmark
      // about history reads rather than synthetic per-row write overhead.
      final sessions = store.box<WorkoutSessionEntity>();
      final exercises = store.box<WorkoutExerciseEntity>();
      final sets = store.box<WorkoutSetEntity>();
      final base = DateTime.utc(2025, 1, 1).millisecondsSinceEpoch;
      store.runInTransaction(TxMode.write, () {
        for (var i = 0; i < 300; i++) {
          final id = 'bulk-$i';
          sessions.put(
            WorkoutSessionEntity(
              uuid: id,
              name: 'Bulk workout $i',
              startedAtMs: base + i * 86400000,
              completedAtMs: base + i * 86400000 + 3600000,
              originalOffsetMinutes: 330,
              updatedAtMs: base + i * 86400000 + 3600000,
              status: WorkoutStatus.completed.name,
            ),
          );
          exercises.put(
            WorkoutExerciseEntity(
              uuid: 'bulk-ex-$i',
              sessionUuid: id,
              definitionUuid: 'bench',
              nameSnapshot: 'Bench press',
              position: 0,
            ),
          );
          for (var j = 0; j < 4; j++) {
            sets.put(
              WorkoutSetEntity(
                uuid: 'bulk-set-$i-$j',
                exerciseUuid: 'bulk-ex-$i',
                position: j,
                kind: WorkoutSetKind.working.name,
                status: WorkoutSetStatus.completed.name,
                reps: 8,
                loadGrams: 50000 + j * 1000,
                completedAtMs: base + i * 86400000 + j * 60000,
                updatedAtMs: base + i * 86400000,
              ),
            );
          }
        }
      });
      final watch = Stopwatch()..start();
      final result = await history.readCompletedAsync();
      watch.stop();
      // CI log records an actual, machine-specific observation; no arbitrary
      // device SLA claimed from a hosted Linux benchmark.
      // ignore: avoid_print
      print(
        'HISTORY_PROFILE completed=300 sets=1200 '
        'worker_read_ms=${watch.elapsedMilliseconds}',
      );
      expect(result.sessions, hasLength(300));
      expect(result.sessions.first.uuid, 'bulk-299');
      expect(calculateWorkoutHistory(result.sessions).loadedWorkingSets, 1200);
    },
  );
}
