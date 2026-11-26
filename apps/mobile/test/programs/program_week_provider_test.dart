import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/catalog/domain/catalog_programs.dart';
import 'package:beyondrep/features/catalog/domain/catalog_templates.dart';
import 'package:beyondrep/features/programs/application/program_providers.dart';
import 'package:beyondrep/features/programs/data/objectbox_program_repository.dart';
import 'package:beyondrep/features/programs/domain/program_models.dart';
import 'package:beyondrep/features/programs/domain/program_schedule.dart';
import 'package:beyondrep/features/programs/domain/program_status.dart';
import 'package:beyondrep/features/workouts/data/objectbox_live_workout_engine.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_repository.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';

import '../train/program_test_support.dart';

/// What the active workout page does after every committed action.
void _afterWorkoutChange(ProviderContainer container) {
  container.invalidate(activeWorkoutProvider);
  container.invalidate(programWeekProvider);
}

void main() {
  late Directory directory;
  late Store store;
  late ProviderContainer container;
  var now = DateTime(2026, 11, 25, 10); // a Wednesday

  /// Imports the synthetic three-day program (push, rest, pull, rest, hidden,
  /// rest, rest) starting on Monday.
  TrainingProgramRecord seed({bool active = true}) {
    final snapshot = programsSnapshot();
    final program = browsablePrograms(snapshot)
        .firstWhere((p) => p.id == 'prog.three');
    final ids = program.week.whereType<String>().toSet();
    return ObjectBoxProgramRepository(store).importProgram(
      requestUuid: 'req-${_seq++}',
      program: program,
      templateRows: {
        for (final id in ids)
          id: templateRowInputs(programTemplate(snapshot, id)!, snapshot),
      },
      templateNames: {
        for (final id in ids) id: programTemplate(snapshot, id)!.name,
      },
      release: 4,
      firstDayWeekday: 1,
      makeActive: active,
      localToday: DateTime(2026, 11, 20),
    );
  }

  setUp(() {
    now = DateTime(2026, 11, 25, 10);
    directory = Directory.systemTemp.createTempSync('beyondrep-week-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    container = ProviderContainer(
      overrides: [
        objectBoxStoreProvider.overrideWithValue(store),
        localNowProvider.overrideWith((ref) => now),
        workoutClockProvider.overrideWithValue(() => now),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    store.close();
    directory.deleteSync(recursive: true);
  });

  ProgramWeek? week() => container.read(programWeekProvider);

  test('is null without an active program', () {
    seed(active: false);
    expect(week(), isNull);
  });

  test('statuses follow the active program and the clock', () {
    seed();
    final w = week()!;
    expect(
      [for (final r in w.rows) r.status],
      [
        ProgramDayStatus.missed,
        ProgramDayStatus.rest,
        ProgramDayStatus.today,
        ProgramDayStatus.rest,
        ProgramDayStatus.upcoming,
        ProgramDayStatus.rest,
        ProgramDayStatus.rest,
      ],
    );
    expect(w.latestMissed!.date, DateTime(2026, 11, 23));
    expect(w.plans.length, 3);
  });

  test('finishing a program-day workout flips that day to done; '
      'discarding does not', () {
    final program = seed();
    // Keep the autoDispose provider alive so only invalidation can refresh it.
    final sub = container.listen(programWeekProvider, (_, _) {});
    addTearDown(sub.close);
    final actions = container.read(workoutActionsProvider);
    final engine = actions;
    final today = week()!.rows[2];
    var session = engine.startProgramDay(
      program,
      expectedPlanUuid: today.day.planUuid,
    );
    _afterWorkoutChange(container);
    expect(week()!.rows[2].status, ProgramDayStatus.today);
    engine.discard(session);
    _afterWorkoutChange(container);
    expect(week()!.rows[2].status, ProgramDayStatus.today);

    session = engine.startProgramDay(
      program,
      expectedPlanUuid: today.day.planUuid,
    );
    engine.finish(session);
    _afterWorkoutChange(container);
    expect(week()!.rows[2].status, ProgramDayStatus.done);
  });

  test('another account store shows only its own programs and sessions', () {
    // Both accounts hold a program and a session with the very same UUIDs.
    TrainingProgramRecord seedIn(Store target) {
      final snapshot = programsSnapshot();
      final program = browsablePrograms(snapshot)
          .firstWhere((p) => p.id == 'prog.three');
      final ids = program.week.whereType<String>().toSet();
      return ObjectBoxProgramRepository(target).importProgram(
        requestUuid: 'shared-program',
        program: program,
        templateRows: {
          for (final id in ids)
            id: templateRowInputs(programTemplate(snapshot, id)!, snapshot),
        },
        templateNames: {
          for (final id in ids) id: programTemplate(snapshot, id)!.name,
        },
        release: 4,
        firstDayWeekday: 1,
        makeActive: true,
        localToday: DateTime(2026, 11, 20),
      );
    }

    void session(Store target, String programUuid, String date) =>
        target.box<WorkoutSessionEntity>().put(
          WorkoutSessionEntity(
            uuid: 'shared-session',
            name: 'S',
            status: 'completed',
            startedAtMs: 1,
            completedAtMs: 2,
            originalOffsetMinutes: 0,
            updatedAtMs: 2,
            programUuid: programUuid,
            programDayLocalDate: date,
          ),
        );

    final a = seedIn(store);
    session(store, a.uuid, '2026-11-25'); // account A did Wednesday

    final otherDir = Directory.systemTemp.createTempSync('beyondrep-other-');
    final other = Store(getObjectBoxModel(), directory: otherDir.path);
    addTearDown(() {
      other.close();
      otherDir.deleteSync(recursive: true);
    });
    final b = seedIn(other);
    expect(b.uuid, a.uuid);
    session(other, b.uuid, '2026-11-23'); // account B did Monday

    final second = ProviderContainer(
      overrides: [
        objectBoxStoreProvider.overrideWithValue(other),
        localNowProvider.overrideWith((ref) => now),
      ],
    );
    addTearDown(second.dispose);

    List<ProgramDayStatus> statuses(ProviderContainer c) => [
      for (final r in c.read(programWeekProvider)!.rows) r.status,
    ];
    expect(statuses(container), [
      ProgramDayStatus.missed, // Monday: not A's
      ProgramDayStatus.rest,
      ProgramDayStatus.done, // Wednesday
      ProgramDayStatus.rest,
      ProgramDayStatus.upcoming,
      ProgramDayStatus.rest,
      ProgramDayStatus.rest,
    ]);
    expect(statuses(second), [
      ProgramDayStatus.done, // Monday
      ProgramDayStatus.rest,
      ProgramDayStatus.today, // Wednesday: not B's
      ProgramDayStatus.rest,
      ProgramDayStatus.upcoming,
      ProgramDayStatus.rest,
      ProgramDayStatus.rest,
    ]);
  });

  test('a session started at 23:50 and finished at 00:10 counts for the '
      'start date, and the new day is not done', () {
    final program = seed();
    final plans = ObjectBoxProgramRepository(store).programPlans(program.uuid);
    final pull = dayFor(program, DateTime(2026, 11, 25)).planUuid!;
    // Make Thursday a training day too (same plan).
    ObjectBoxProgramRepository(store).setDayPlan(program.uuid, 3, pull);
    expect(plans, isNotEmpty);
    final fresh = ObjectBoxProgramRepository(store).getProgram(program.uuid)!;

    now = DateTime(2026, 11, 25, 23, 50);
    final actions = container.read(workoutActionsProvider);
    final started = actions.startProgramDay(fresh, expectedPlanUuid: pull);
    expect(started.programDayLocalDate, '2026-11-25');

    now = DateTime(2026, 11, 26, 0, 10);
    container
        .read(liveWorkoutEngineProvider)
        .finishWorkout(
          started.uuid,
          expectedRevision: started.revision,
          finishedAtUtc: now.toUtc(),
        );
    container.invalidate(programWeekProvider);
    final rows = week()!.rows;
    expect(rows[2].date, DateTime(2026, 11, 25));
    expect(rows[2].status, ProgramDayStatus.done);
    expect(rows[3].date, DateTime(2026, 11, 26));
    expect(rows[3].status, ProgramDayStatus.today);
  });

  test('listProgramSessions returns only finished, undeleted sessions of that '
      'program with a program day', () {
    final program = seed();
    final repo = ObjectBoxWorkoutRepository(store);
    final box = store.box<WorkoutSessionEntity>();
    WorkoutSessionEntity entity(
      String uuid, {
      String status = 'completed',
      String? programUuid,
      String? date = '2026-11-23',
      int? deletedAtMs,
    }) => WorkoutSessionEntity(
      uuid: uuid,
      name: uuid,
      status: status,
      startedAtMs: 1,
      originalOffsetMinutes: 0,
      updatedAtMs: 1,
      programUuid: programUuid,
      programDayLocalDate: date,
      deletedAtMs: deletedAtMs,
    );
    box.putMany([
      entity('keep', programUuid: program.uuid),
      entity('discarded', status: 'discarded', programUuid: program.uuid),
      entity('deleted', programUuid: program.uuid, deletedAtMs: 5),
      entity('other', programUuid: 'other-program'),
      entity('plain', programUuid: null, date: null),
    ]);
    expect(
      [for (final s in repo.listProgramSessions(program.uuid)) s.uuid],
      ['keep'],
    );
  });
}

var _seq = 0;
