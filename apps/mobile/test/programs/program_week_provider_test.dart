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
import 'package:beyondrep/features/programs/domain/program_status.dart';
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

  test('another account store shows only its own programs', () {
    seed();
    final otherDir = Directory.systemTemp.createTempSync('beyondrep-other-');
    final other = Store(getObjectBoxModel(), directory: otherDir.path);
    addTearDown(() {
      other.close();
      otherDir.deleteSync(recursive: true);
    });
    final second = ProviderContainer(
      overrides: [
        objectBoxStoreProvider.overrideWithValue(other),
        localNowProvider.overrideWith((ref) => now),
      ],
    );
    addTearDown(second.dispose);
    expect(second.read(programWeekProvider), isNull);
    expect(week(), isNotNull);
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
