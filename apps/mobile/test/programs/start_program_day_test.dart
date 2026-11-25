import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/features/programs/domain/program_models.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/workouts/data/objectbox_live_workout_engine.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_repository.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';

class _Ids implements UuidFactory {
  var next = 0;
  @override
  String newId() =>
      '00000000-0000-4000-8000-${(next++).toString().padLeft(12, '0')}';
}

void main() {
  late Directory directory;
  late Store store;
  late ObjectBoxLiveWorkoutEngine engine;
  late ObjectBoxWorkoutLibraryRepository library;
  late RepositoryWorkoutActions actions;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-start-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    engine = ObjectBoxLiveWorkoutEngine(store);
    library = ObjectBoxWorkoutLibraryRepository(store)..ensureCatalogSeeded();
    actions = RepositoryWorkoutActions(
      engine,
      ObjectBoxWorkoutRepository(store),
      library,
      _Ids(),
    );
    for (final (uuid, program) in [('plan-a', 'prog-1'), ('own', null)]) {
      library.savePlan(
        uuid: uuid,
        name: uuid,
        description: '',
        exercises: const [],
      );
      final entity = store.box<WorkoutPlanEntity>().getAll().firstWhere(
        (p) => p.uuid == uuid,
      );
      entity.programUuid = program;
      store.box<WorkoutPlanEntity>().put(entity);
    }
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  // First day Wednesday: 2026-11-25 is a Wednesday and day 0.
  TrainingProgramRecord program({String uuid = 'prog-1'}) =>
      TrainingProgramRecord(
        uuid: uuid,
        name: 'P',
        description: '',
        sourceId: 'prog.x',
        sourceRelease: 4,
        firstDayWeekday: 3,
        isActive: true,
        updatedAtMs: 0,
        days: [
          const ProgramDayRecord(uuid: 'd0', dayIndex: 0, planUuid: 'plan-a'),
          const ProgramDayRecord(uuid: 'd1', dayIndex: 1),
          for (var i = 2; i < 7; i++)
            ProgramDayRecord(uuid: 'd$i', dayIndex: i),
        ],
      );

  test('a program-day start stores both fields', () {
    final session = actions.startProgramDay(
      program(),
      DateTime(2026, 11, 25, 23, 50),
    );
    expect(session.programUuid, 'prog-1');
    expect(session.programDayLocalDate, '2026-11-25');
    expect(session.planUuid, 'plan-a');
    final stored = store.box<WorkoutSessionEntity>().getAll().single;
    expect(stored.programUuid, 'prog-1');
    expect(stored.programDayLocalDate, '2026-11-25');
  });

  test('a plain start of the same plan stores nulls', () {
    final session = actions.startPlan('plan-a');
    expect(session.programUuid, isNull);
    expect(session.programDayLocalDate, isNull);
  });

  test('a rest day throws StateError and writes nothing', () {
    expect(
      () => actions.startProgramDay(program(), DateTime(2026, 11, 26)),
      throwsStateError,
    );
    expect(store.box<WorkoutSessionEntity>().count(), 0);
  });

  test('a mismatched program throws and writes nothing', () {
    for (final planUuid in ['plan-a', 'own']) {
      expect(
        () => engine.startWorkout(
          sessionUuid: 's1',
          planUuid: planUuid,
          programDay: (programUuid: 'other', localDate: '2026-11-25'),
          startedAtUtc: DateTime.utc(2026, 11, 25),
          originalOffsetMinutes: 0,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => engine.startWorkout(
        sessionUuid: 's1',
        quickName: 'Quick',
        programDay: (programUuid: 'prog-1', localDate: '2026-11-25'),
        startedAtUtc: DateTime.utc(2026, 11, 25),
        originalOffsetMinutes: 0,
      ),
      throwsArgumentError,
    );
    expect(store.box<WorkoutSessionEntity>().count(), 0);
  });

  test('replay is idempotent and a changed program day conflicts', () {
    DateTime.now();
    final at = DateTime.utc(2026, 11, 25, 9);
    for (var i = 0; i < 2; i++) {
      engine.startWorkout(
        sessionUuid: 's1',
        planUuid: 'plan-a',
        programDay: (programUuid: 'prog-1', localDate: '2026-11-25'),
        startedAtUtc: at,
        originalOffsetMinutes: 0,
      );
    }
    expect(store.box<WorkoutSessionEntity>().count(), 1);
    expect(
      () => engine.startWorkout(
        sessionUuid: 's1',
        planUuid: 'plan-a',
        programDay: (programUuid: 'prog-1', localDate: '2026-11-24'),
        startedAtUtc: at,
        originalOffsetMinutes: 0,
      ),
      throwsStateError,
    );
    expect(
      () => engine.startWorkout(
        sessionUuid: 's1',
        planUuid: 'plan-a',
        startedAtUtc: at,
        originalOffsetMinutes: 0,
      ),
      throwsStateError,
    );
  });

  test('another unfinished workout blocks the start', () {
    actions.startQuick('Quick');
    expect(
      () => actions.startProgramDay(program(), DateTime(2026, 11, 25)),
      throwsStateError,
    );
  });
}
