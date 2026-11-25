import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';

import 'fixtures/objectbox_pre_duration.g.dart' as pre_duration;

void main() {
  test('pre-duration database upgrades with null seconds fields', () {
    final dir = Directory.systemTemp.createTempSync('beyondrep-duration-');
    try {
      final old = Store(pre_duration.getObjectBoxModel(), directory: dir.path);
      old.box<WorkoutSetEntity>().put(
        WorkoutSetEntity(
          uuid: '00000000-0000-4000-8000-000000000301',
          exerciseUuid: '00000000-0000-4000-8000-000000000201',
          position: 0,
          status: 'completed',
          reps: 8,
          updatedAtMs: 1,
        ),
      );
      old.box<PlanExerciseEntity>().put(
        PlanExerciseEntity(
          uuid: '00000000-0000-4000-8000-000000000401',
          planUuid: '00000000-0000-4000-8000-000000000501',
          exerciseUuid: 'builtin.v1.squat',
          position: 0,
          targetSets: 3,
          targetRepsMin: 5,
        ),
      );
      old.close();

      final upgraded = Store(getObjectBoxModel(), directory: dir.path);
      try {
        final set = upgraded.box<WorkoutSetEntity>().getAll().single;
        final row = upgraded.box<PlanExerciseEntity>().getAll().single;
        expect(set.reps, 8);
        expect(set.durationSeconds, isNull);
        expect(row.targetRepsMin, 5);
        expect(row.targetDurationSeconds, isNull);

        set
          ..reps = null
          ..durationSeconds = 45;
        row
          ..targetRepsMin = null
          ..targetDurationSeconds = 60;
        upgraded.box<WorkoutSetEntity>().put(set);
        upgraded.box<PlanExerciseEntity>().put(row);

        expect(
          upgraded.box<WorkoutSetEntity>().getAll().single.durationSeconds,
          45,
        );
        expect(
          upgraded
              .box<PlanExerciseEntity>()
              .getAll()
              .single
              .targetDurationSeconds,
          60,
        );
      } finally {
        upgraded.close();
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
