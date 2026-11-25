import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';

import 'fixtures/objectbox_pre_muscles.g.dart' as pre_muscles;

void main() {
  test('pre-muscles database upgrades with empty muscle lists', () {
    final dir = Directory.systemTemp.createTempSync('beyondrep-muscles-');
    try {
      final old = Store(pre_muscles.getObjectBoxModel(), directory: dir.path);
      old.box<ExerciseDefinitionEntity>().put(
        ExerciseDefinitionEntity(
          uuid: 'builtin.v1.squat',
          name: 'Squat',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      );
      old.box<WorkoutExerciseEntity>().put(
        WorkoutExerciseEntity(
          uuid: '00000000-0000-4000-8000-000000000201',
          sessionUuid: '00000000-0000-4000-8000-000000000101',
          nameSnapshot: 'Squat',
          position: 0,
        ),
      );
      old.close();

      final upgraded = Store(getObjectBoxModel(), directory: dir.path);
      try {
        final definition = upgraded
            .box<ExerciseDefinitionEntity>()
            .getAll()
            .single;
        final exercise = upgraded.box<WorkoutExerciseEntity>().getAll().single;
        expect(definition.primaryMuscles, isEmpty);
        expect(definition.secondaryMuscles, isEmpty);
        expect(exercise.primaryMusclesSnapshot, isEmpty);
        expect(exercise.secondaryMusclesSnapshot, isEmpty);

        definition
          ..primaryMuscles = ['quads', 'glutes']
          ..secondaryMuscles = ['hamstrings'];
        exercise
          ..primaryMusclesSnapshot = ['quads', 'glutes']
          ..secondaryMusclesSnapshot = ['hamstrings'];
        upgraded.box<ExerciseDefinitionEntity>().put(definition);
        upgraded.box<WorkoutExerciseEntity>().put(exercise);

        final d = upgraded.box<ExerciseDefinitionEntity>().getAll().single;
        final e = upgraded.box<WorkoutExerciseEntity>().getAll().single;
        expect(d.primaryMuscles, ['quads', 'glutes']);
        expect(d.secondaryMuscles, ['hamstrings']);
        expect(e.primaryMusclesSnapshot, ['quads', 'glutes']);
        expect(e.secondaryMusclesSnapshot, ['hamstrings']);
      } finally {
        upgraded.close();
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
