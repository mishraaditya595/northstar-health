import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';

import 'fixtures/objectbox_pre_exercise_rest.g.dart' as pre_rest;

void main() {
  test('pre-rest database upgrades with null session exercise rest', () {
    final dir = Directory.systemTemp.createTempSync('beyondrep-ex-rest-');
    try {
      final old = Store(pre_rest.getObjectBoxModel(), directory: dir.path);
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
        final row = upgraded.box<WorkoutExerciseEntity>().getAll().single;
        expect(row.nameSnapshot, 'Squat');
        expect(row.restSeconds, isNull);
        row.restSeconds = 75;
        upgraded.box<WorkoutExerciseEntity>().put(row);
        expect(
          upgraded.box<WorkoutExerciseEntity>().getAll().single.restSeconds,
          75,
        );
      } finally {
        upgraded.close();
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
