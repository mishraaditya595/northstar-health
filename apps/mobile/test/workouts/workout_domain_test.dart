import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/ids/uuid_factory.dart';
import 'package:northstar_health/core/units/load_units.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';

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
}
