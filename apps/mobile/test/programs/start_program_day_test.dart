import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/features/programs/domain/program_models.dart';
import 'package:beyondrep/features/programs/domain/program_status.dart';
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
  var clock = DateTime(2026, 11, 25, 10);

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
      clock: () => clock,
    );
    for (final (uuid, program) in [
      ('plan-a', 'prog-1'),
      ('plan-b', 'prog-1'),
      ('own', null),
    ]) {
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
  TrainingProgramRecord program({
    String uuid = 'prog-1',
    bool isActive = true,
    String? activated = '2026-11-25',
  }) => TrainingProgramRecord(
    uuid: uuid,
    activatedLocalDate: activated,
    name: 'P',
    description: '',
    sourceId: 'prog.x',
    sourceRelease: 4,
    firstDayWeekday: 3,
    isActive: isActive,
    updatedAtMs: 0,
    days: [
      const ProgramDayRecord(uuid: 'd0', dayIndex: 0, planUuid: 'plan-a'),
      const ProgramDayRecord(uuid: 'd1', dayIndex: 1),
      for (var i = 2; i < 7; i++) ProgramDayRecord(uuid: 'd$i', dayIndex: i),
    ],
  );

  test('a program-day start stores both fields', () {
    clock = DateTime(2026, 11, 25, 23, 50);
    final session = actions.startProgramDay(
      program(),
      expectedPlanUuid: 'plan-a',
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
    clock = DateTime(2026, 11, 26);
    expect(
      () => actions.startProgramDay(program(), expectedPlanUuid: null),
      throwsStateError,
    );
    expect(store.box<WorkoutSessionEntity>().count(), 0);
  });

  test('the clock moving past midnight after the screen was built does '
      'not start; the day the screen showed is not recorded', () {
    clock = DateTime(2026, 11, 26, 0, 5); // now a rest day
    expect(
      () => actions.startProgramDay(program(), expectedPlanUuid: 'plan-a'),
      throwsA(isA<ProgramDayChanged>()),
    );
    expect(store.box<WorkoutSessionEntity>().count(), 0);
  });

  test('a different plan than the screen showed does not start', () {
    clock = DateTime(2026, 11, 25, 9);
    expect(
      () => actions.startProgramDay(program(), expectedPlanUuid: 'other'),
      throwsA(isA<ProgramDayChanged>()),
    );
    expect(store.box<WorkoutSessionEntity>().count(), 0);
  });

  test('the start time comes from the clock at the tap', () {
    clock = DateTime(2026, 11, 25, 18, 30);
    final session = actions.startProgramDay(
      program(),
      expectedPlanUuid: 'plan-a',
    );
    expect(session.startedAtUtc, clock.toUtc());
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
      () => actions.startProgramDay(program(), expectedPlanUuid: 'plan-a'),
      throwsStateError,
    );
  });
  group('only the active program starts', () {
    test('an inactive program throws and writes nothing', () {
      clock = DateTime(2026, 11, 25, 10);
      expect(
        () => actions.startProgramDay(
          program(isActive: false),
          expectedPlanUuid: 'plan-a',
        ),
        throwsStateError,
      );
      expect(store.box<WorkoutSessionEntity>().count(), 0);
    });
  });

  group('starting a missed day', () {
    // Wednesday plan-a, Thursday plan-b; today is Friday 2026-11-27.
    TrainingProgramRecord week({String? activated = '2026-11-25'}) =>
        TrainingProgramRecord(
          uuid: 'prog-1',
          name: 'P',
          description: '',
          sourceId: 'prog.x',
          sourceRelease: 4,
          firstDayWeekday: 3,
          isActive: true,
          activatedLocalDate: activated,
          updatedAtMs: 0,
          days: [
            const ProgramDayRecord(uuid: 'd0', dayIndex: 0, planUuid: 'plan-a'),
            const ProgramDayRecord(uuid: 'd1', dayIndex: 1, planUuid: 'plan-b'),
            for (var i = 2; i < 7; i++)
              ProgramDayRecord(uuid: 'd$i', dayIndex: i),
          ],
        );

    setUp(() => clock = DateTime(2026, 11, 27, 18, 30));

    test(
      'stores the missed date, the start time is now, and the day is done',
      () {
        final session = actions.startProgramDay(
          week(),
          expectedPlanUuid: 'plan-b',
          missedDate: DateTime(2026, 11, 26),
        );
        expect(session.programUuid, 'prog-1');
        expect(session.programDayLocalDate, '2026-11-26');
        expect(session.planUuid, 'plan-b');
        expect(session.startedAtUtc, clock.toUtc());
        engine.finishWorkout(
          session.uuid,
          expectedRevision: session.revision,
          finishedAtUtc: clock.toUtc(),
        );
        final rows = programWeekStatus(
          program: week(),
          localToday: clock,
          sessions: ObjectBoxWorkoutRepository(store)
              .listProgramSessions('prog-1'),
          availablePlanUuids: {'plan-a', 'plan-b'},
        );
        expect(rows[1].status, ProgramDayStatus.done);
        expect(rows[0].status, ProgramDayStatus.missed);
      },
    );

    test('a date that is now done throws ProgramDayChanged', () {
      final first = actions.startProgramDay(
        week(),
        expectedPlanUuid: 'plan-b',
        missedDate: DateTime(2026, 11, 26),
      );
      engine.finishWorkout(
        first.uuid,
        expectedRevision: first.revision,
        finishedAtUtc: clock.toUtc(),
      );
      expect(
        () => actions.startProgramDay(
          week(),
          expectedPlanUuid: 'plan-b',
          missedDate: DateTime(2026, 11, 26),
        ),
        throwsA(isA<ProgramDayChanged>()),
      );
      expect(store.box<WorkoutSessionEntity>().count(), 1);
    });

    test('a date that is now a rest day after an edit throws', () {
      final edited = TrainingProgramRecord(
        uuid: 'prog-1',
        name: 'P',
        description: '',
        sourceId: 'prog.x',
        sourceRelease: 4,
        firstDayWeekday: 3,
        isActive: true,
        activatedLocalDate: '2026-11-25',
        updatedAtMs: 0,
        days: [
          const ProgramDayRecord(uuid: 'd0', dayIndex: 0, planUuid: 'plan-a'),
          for (var i = 1; i < 7; i++)
            ProgramDayRecord(uuid: 'd$i', dayIndex: i),
        ],
      );
      expect(
        () => actions.startProgramDay(
          edited,
          expectedPlanUuid: 'plan-b',
          missedDate: DateTime(2026, 11, 26),
        ),
        throwsA(isA<ProgramDayChanged>()),
      );
      expect(store.box<WorkoutSessionEntity>().count(), 0);
    });

    test('a plan that differs from the one shown throws', () {
      expect(
        () => actions.startProgramDay(
          week(),
          expectedPlanUuid: 'plan-a',
          missedDate: DateTime(2026, 11, 26),
        ),
        throwsA(isA<ProgramDayChanged>()),
      );
    });

    test('dates outside the window throw: today, future, last week, before '
        'activation', () {
      for (final (date, activated) in [
        (DateTime(2026, 11, 27), '2026-11-25'), // today
        (DateTime(2026, 11, 28), '2026-11-25'), // future
        (DateTime(2026, 11, 19), '2026-11-25'), // previous week
        (DateTime(2026, 11, 25), '2026-11-26'), // before activation
      ]) {
        expect(
          () => actions.startProgramDay(
            week(activated: activated),
            expectedPlanUuid: 'plan-a',
            missedDate: date,
          ),
          throwsA(isA<ProgramDayChanged>()),
          reason: '$date',
        );
      }
      expect(store.box<WorkoutSessionEntity>().count(), 0);
    });

    test('an inactive program cannot start a missed day', () {
      expect(
        () => actions.startProgramDay(
          TrainingProgramRecord(
            uuid: 'prog-1',
            name: 'P',
            description: '',
            sourceId: 'prog.x',
            sourceRelease: 4,
            firstDayWeekday: 3,
            isActive: false,
            activatedLocalDate: '2026-11-25',
            updatedAtMs: 0,
            days: week().days,
          ),
          expectedPlanUuid: 'plan-b',
          missedDate: DateTime(2026, 11, 26),
        ),
        throwsStateError,
      );
      expect(store.box<WorkoutSessionEntity>().count(), 0);
    });

    test('another unfinished workout blocks the start', () {
      actions.startQuick('Quick');
      expect(
        () => actions.startProgramDay(
          week(),
          expectedPlanUuid: 'plan-b',
          missedDate: DateTime(2026, 11, 26),
        ),
        throwsStateError,
      );
    });
  });
}
