import 'package:flutter_test/flutter_test.dart';
import 'package:beyondrep/core/units/load_units.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:beyondrep/features/workouts/domain/workout_status_codec.dart';

void main() {
  test('frozen storage names do not throw on future schema values', () {
    expect(workoutStatusFromStorage('paused'), WorkoutStatus.paused);
    expect(workoutStatusFromStorage('scheduled'), WorkoutStatus.unknown);
    expect(workoutSetStatusFromStorage('skipped'), WorkoutSetStatus.skipped);
    expect(workoutSetStatusFromStorage('partial'), WorkoutSetStatus.unknown);
    expect(workoutSetKindFromStorage('working'), WorkoutSetKind.working);
    expect(workoutSetKindFromStorage('negative'), WorkoutSetKind.unknown);
    expect(loadUnitFromStorage('lb'), LoadUnit.lb);
    expect(loadUnitFromStorage('g'), LoadUnit.unknown);
    expect(
      () => LoadUnits.fromGrams(1000, LoadUnit.unknown),
      throwsArgumentError,
    );
  });
}
