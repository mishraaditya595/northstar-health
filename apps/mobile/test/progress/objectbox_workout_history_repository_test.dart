import 'dart:io';

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

  void create(String id, DateTime start, {bool finish = true,
      bool discard = false}) {
    engine.startWorkout(
      sessionUuid: id, quickName: 'Session $id',
      startedAtUtc: start, originalOffsetMinutes: 330,
    );
    editor.addExercise(WorkoutExerciseRecord(
      uuid: 'exercise-$id', sessionUuid: id,
      definitionUuid: 'builtin.v1.bench-press',
      nameSnapshot: 'Bench press', position: 0,
    ));
    final current = editor.getSession(id)!;
    editor.saveSet(
      sessionUuid: id, expectedRevision: current.revision,
      set: WorkoutSetRecord(
        uuid: 'set-$id', exerciseUuid: 'exercise-$id',
        position: 0, kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.completed, reps: 8, loadGrams: 62500,
        completedAtUtc: start.add(const Duration(minutes: 5)),
      ),
    );
    final updated = editor.getSession(id)!;
    if (finish) {
      engine.finishWorkout(
        id, expectedRevision: updated.revision,
        finishedAtUtc: start.add(const Duration(minutes: 20)),
      );
    } else if (discard) {
      engine.discardWorkout(id, expectedRevision: updated.revision);
    }
  }

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
    create('discard', DateTime.utc(2026, 10, 22, 8),
        finish: false, discard: true);
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
    expect(history.readCompleted().sessions.map((s) => s.uuid),
        ['late', 'early']);
  });
}
