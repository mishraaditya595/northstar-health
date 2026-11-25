import 'package:flutter_test/flutter_test.dart';
import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/core/units/load_units.dart';
import 'package:beyondrep/features/workouts/domain/durations.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';

void main() {
  test('UUIDs are distinct RFC-4122 version 4 strings', () {
    final factory = SecureUuidFactory();
    final values = List.generate(128, (_) => factory.newId());
    final regex = RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
    );
    expect(values.every(regex.hasMatch), isTrue);
    expect(values.toSet(), hasLength(values.length));
  });

  test('weight conversion is canonical and rejects invalid values', () {
    expect(LoadUnits.toGrams(100, LoadUnit.kg), 100000);
    expect(LoadUnits.toGrams(100, LoadUnit.lb), 45359);
    expect(LoadUnits.fromGrams(45359, LoadUnit.lb), closeTo(100, 0.01));
    expect(
      () => LoadUnits.toGrams(double.nan, LoadUnit.kg),
      throwsArgumentError,
    );
    expect(() => LoadUnits.toGrams(-1, LoadUnit.lb), throwsArgumentError);
  });

  test(
    'missing values remain absent; complete requires real reps and time',
    () {
      const planned = WorkoutSetRecord(
        uuid: 'set-1',
        exerciseUuid: 'e1',
        position: 0,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.planned,
      );
      planned.validate();
      expect(planned.reps, isNull);
      expect(planned.loadGrams, isNull);
      expect(
        () => const WorkoutSetRecord(
          uuid: 'set-2',
          exerciseUuid: 'e1',
          position: 1,
          kind: WorkoutSetKind.working,
          status: WorkoutSetStatus.completed,
        ).validate(),
        throwsArgumentError,
      );
    },
  );

  test('formatDurationSeconds renders seconds, minutes and leftovers', () {
    expect(formatDurationSeconds(1), '1 s');
    expect(formatDurationSeconds(45), '45 s');
    expect(formatDurationSeconds(60), '1 min');
    expect(formatDurationSeconds(90), '1 min 30 s');
    expect(formatDurationSeconds(3600), '60 min');
  });

  group('timed sets', () {
    WorkoutSetRecord timed({
      int? reps,
      int? seconds,
      WorkoutSetStatus status = WorkoutSetStatus.completed,
      DateTime? at,
    }) => WorkoutSetRecord(
      uuid: 's',
      exerciseUuid: 'e1',
      position: 0,
      kind: WorkoutSetKind.working,
      status: status,
      reps: reps,
      durationSeconds: seconds,
      completedAtUtc: at ?? DateTime.utc(2026, 11, 26),
    );

    test('a completed set with seconds only is valid', () {
      timed(seconds: 45).validate();
      timed(seconds: 1).validate();
      timed(seconds: 86400).validate();
    });
    test('seconds outside 1 to 86400 are rejected', () {
      expect(() => timed(seconds: 0).validate(), throwsArgumentError);
      expect(() => timed(seconds: 86401).validate(), throwsArgumentError);
      expect(
        () => timed(seconds: -3, status: WorkoutSetStatus.planned).validate(),
        throwsArgumentError,
      );
    });
    test('reps and seconds together are rejected', () {
      expect(() => timed(reps: 5, seconds: 45).validate(), throwsArgumentError);
    });
    test('a completed set needs reps or seconds, and a time', () {
      expect(() => timed().validate(), throwsArgumentError);
      expect(
        () => const WorkoutSetRecord(
          uuid: 's',
          exerciseUuid: 'e1',
          position: 0,
          kind: WorkoutSetKind.working,
          status: WorkoutSetStatus.completed,
          durationSeconds: 45,
        ).validate(),
        throwsArgumentError,
      );
    });
  });

  group('plan seconds target', () {
    PlanExerciseRecord row({int? seconds, int? min, int? max}) =>
        PlanExerciseRecord(
          uuid: 'p',
          exerciseUuid: 'e',
          position: 0,
          targetSets: 3,
          targetRepsMin: min,
          targetRepsMax: max,
          targetDurationSeconds: seconds,
        );
    test('seconds target 1 to 3600 is valid and survives withPosition', () {
      row(seconds: 45).validate();
      row(seconds: 3600).validate();
      expect(row(seconds: 45).withPosition(2).targetDurationSeconds, 45);
    });
    test('out of range or beside reps targets is rejected', () {
      expect(() => row(seconds: 0).validate(), throwsArgumentError);
      expect(() => row(seconds: 3601).validate(), throwsArgumentError);
      expect(() => row(seconds: 45, min: 5).validate(), throwsArgumentError);
      expect(() => row(seconds: 45, max: 8).validate(), throwsArgumentError);
    });
  });
}
