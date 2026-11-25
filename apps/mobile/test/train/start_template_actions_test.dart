import 'dart:io';

import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/features/catalog/domain/catalog_templates.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/workouts/data/objectbox_live_workout_engine.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_repository.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_fixtures.dart';
import '../catalog/catalog_templates_test.dart' show rx, template;

void main() {
  late Directory directory;
  late Store store;
  late RepositoryWorkoutActions actions;
  late ObjectBoxLiveWorkoutEngine engine;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-start-tpl-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    engine = ObjectBoxLiveWorkoutEngine(store);
    actions = RepositoryWorkoutActions(
      engine,
      ObjectBoxWorkoutRepository(store),
      ObjectBoxWorkoutLibraryRepository(store),
      SecureUuidFactory(),
    );
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  final snapshot = catalogSnapshotOf([
    catalogExercise('builtin.v1.synthetic-press', 'Synthetic press'),
    catalogExercise(
      'builtin.v1.synthetic-hold',
      'Synthetic hold',
      mode: 'duration',
    ),
  ]);
  final t = template('tpl.x', [
    rx('builtin.v1.synthetic-press'),
    rx('builtin.v1.synthetic-hold', seconds: 30),
  ], name: 'Synthetic day');

  test('materializes the exercises and starts an unsaved workout', () {
    final session = actions.startTemplate(
      t.name,
      templateRowInputs(t, snapshot),
      snapshot.release,
    );
    expect(session.name, 'Synthetic day');
    expect(session.planUuid, isNull);
    expect(session.exercises.map((e) => e.nameSnapshot), [
      'Synthetic press',
      'Synthetic hold',
    ]);
    expect(store.box<WorkoutPlanEntity>().count(), 0);
  });

  test('an unfinished workout blocks the start and changes nothing', () {
    actions.startQuick('Already going');
    final definitions = store.box<ExerciseDefinitionEntity>().count();
    expect(
      () => actions.startTemplate(
        t.name,
        templateRowInputs(t, snapshot),
        snapshot.release,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Finish or discard the existing workout first',
        ),
      ),
    );
    expect(store.box<WorkoutSessionEntity>().count(), 1);
    expect(store.box<ExerciseDefinitionEntity>().count(), definitions);
  });
}
