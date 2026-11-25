import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/features/workouts/data/objectbox_live_workout_engine.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_outbox.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_repository.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:beyondrep/objectbox.g.dart';

import 'fixtures/objectbox_pre_programs.g.dart' as pre_programs;

class _FixedUuid implements UuidFactory {
  @override
  String newId() => '00000000-0000-4000-8000-000000000401';
}

void main() {
  test('pre-programs database upgrades with null program fields', () {
    final dir = Directory.systemTemp.createTempSync('beyondrep-programs-');
    try {
      final old = Store(pre_programs.getObjectBoxModel(), directory: dir.path);
      old.box<WorkoutPlanEntity>().put(
        WorkoutPlanEntity(
          uuid: '00000000-0000-4000-8000-000000000001',
          name: 'Old plan',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      );
      old.box<WorkoutSessionEntity>().put(
        WorkoutSessionEntity(
          uuid: '00000000-0000-4000-8000-000000000101',
          name: 'Old session',
          startedAtMs: 1,
          originalOffsetMinutes: 0,
          updatedAtMs: 1,
        ),
      );
      old.close();

      final upgraded = Store(getObjectBoxModel(), directory: dir.path);
      try {
        final plan = upgraded.box<WorkoutPlanEntity>().getAll().single;
        expect(plan.name, 'Old plan');
        expect(plan.programUuid, isNull);
        final session = upgraded.box<WorkoutSessionEntity>().getAll().single;
        expect(session.programUuid, isNull);
        expect(session.programDayLocalDate, isNull);
        expect(upgraded.box<TrainingProgramEntity>().isEmpty(), isTrue);
        expect(upgraded.box<ProgramDayEntity>().isEmpty(), isTrue);
      } finally {
        upgraded.close();
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('program entities round-trip', () {
    final dir = Directory.systemTemp.createTempSync('beyondrep-programs-');
    final store = Store(getObjectBoxModel(), directory: dir.path);
    try {
      store.box<TrainingProgramEntity>().put(
        TrainingProgramEntity(
          uuid: 'p1',
          name: 'Synthetic program',
          description: 'D',
          sourceId: 'prog.synthetic',
          sourceRelease: 4,
          firstDayWeekday: 3,
          isActive: true,
          activatedLocalDate: '2026-11-25',
          createdAtMs: 1,
          updatedAtMs: 2,
        ),
      );
      store.box<ProgramDayEntity>().put(
        ProgramDayEntity(uuid: 'd1', programUuid: 'p1', dayIndex: 2),
      );
      final program = store.box<TrainingProgramEntity>().getAll().single;
      expect(program.firstDayWeekday, 3);
      expect(program.isActive, isTrue);
      expect(program.activatedLocalDate, '2026-11-25');
      expect(program.archivedAtMs, isNull);
      final day = store.box<ProgramDayEntity>().getAll().single;
      expect([day.programUuid, day.dayIndex, day.planUuid], ['p1', 2, null]);
    } finally {
      store.close();
      dir.deleteSync(recursive: true);
    }
  });

  test('program fields never reach the cloud upload payload', () {
    final dir = Directory.systemTemp.createTempSync('beyondrep-programs-');
    final store = Store(getObjectBoxModel(), directory: dir.path);
    try {
      final outbox = ObjectBoxWorkoutOutbox(store, uuidFactory: _FixedUuid());
      final engine = ObjectBoxLiveWorkoutEngine(store, outbox: outbox);
      final repository = ObjectBoxWorkoutRepository(store);
      const id = '00000000-0000-4000-8000-000000000101';
      engine.startWorkout(
        sessionUuid: id,
        quickName: 'Synthetic',
        startedAtUtc: DateTime.utc(2026, 10, 25, 9),
        originalOffsetMinutes: 0,
      );
      final entity = store.box<WorkoutSessionEntity>().getAll().single;
      entity.programUuid = 'p1';
      entity.programDayLocalDate = '2026-10-25';
      store.box<WorkoutSessionEntity>().put(entity);
      repository.addExercise(
        WorkoutExerciseRecord(
          uuid: '00000000-0000-4000-8000-000000000201',
          sessionUuid: id,
          nameSnapshot: 'Squat',
          position: 0,
        ),
      );
      engine.finishWorkout(
        id,
        expectedRevision: repository.getSession(id)!.revision,
        finishedAtUtc: DateTime.utc(2026, 10, 25, 10),
      );
      final payload = outbox.pending().single.payloadJson;
      final dto = jsonDecode(payload) as Map<String, dynamic>;
      expect(
        dto.keys.where((k) => k.toLowerCase().contains('program')),
        isEmpty,
      );
      expect(payload.toLowerCase(), isNot(contains('program')));
    } finally {
      store.close();
      dir.deleteSync(recursive: true);
    }
  });
}
