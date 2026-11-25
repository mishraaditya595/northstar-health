import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/catalog/domain/exercise_choices.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogExercise cat(
  String id,
  String name, {
  List<String> aliases = const [],
  String group = 'Legs',
  List<String> equipment = const ['barbell'],
  String mode = 'reps_load',
  bool retired = false,
}) => CatalogExercise(
  id: id,
  name: name,
  aliases: aliases,
  muscleGroup: group,
  primaryMuscles: const ['quads'],
  secondaryMuscles: const [],
  equipment: equipment,
  category: 'squat',
  mode: mode,
  cues: const [],
  retired: retired,
);

CatalogSnapshot snapshotOf(List<CatalogExercise> exercises) => CatalogSnapshot(
  release: 4,
  schemaVersion: 1,
  minAppCatalogSchema: 1,
  publishedAt: '2026-11-26T00:00:00Z',
  sha256: 'a' * 64,
  exercises: exercises,
  templates: const [],
  programs: const [],
);

ExerciseRecord local(
  String id,
  String name, {
  bool builtIn = true,
  int? archivedAtMs,
  String group = 'Legs',
  String equipment = 'Barbell',
  String mode = 'reps_load',
}) => ExerciseRecord(
  uuid: id,
  name: name,
  muscleGroup: group,
  equipment: equipment,
  movementCategory: 'Squat',
  inputMode: mode,
  isBuiltIn: builtIn,
  updatedAtMs: 1,
  archivedAtMs: archivedAtMs,
);

void main() {
  test('merges catalogue and local by id', () {
    final choices = buildExerciseChoices(
      local: [local('builtin.v1.squat', 'Barbell back squat')],
      catalog: snapshotOf([
        cat('builtin.v1.squat', 'Back squat', aliases: ['Squat']),
      ]),
    );
    expect(choices, hasLength(1));
    final choice = choices.single;
    expect(choice.id, 'builtin.v1.squat');
    expect(choice.name, 'Back squat', reason: 'catalogue name wins');
    expect(choice.aliases, ['Squat']);
    expect(choice.local?.uuid, 'builtin.v1.squat');
    expect(choice.catalog, isNotNull);
    expect(choice.isCustom, isFalse);
  });

  test('catalogue-only exercise has no local record', () {
    final choices = buildExerciseChoices(
      local: const [],
      catalog: snapshotOf([cat('builtin.v1.row', 'Barbell row')]),
    );
    expect(choices.single.local, isNull);
    expect(choices.single.catalog?.id, 'builtin.v1.row');
    expect(choices.single.mode, 'reps_load');
    expect(choices.single.muscleGroup, 'Legs');
  });

  test('local built-ins appear without a catalogue', () {
    final choices = buildExerciseChoices(
      local: [local('builtin.v1.squat', 'Barbell back squat')],
    );
    expect(choices.single.name, 'Barbell back squat');
    expect(choices.single.equipment, 'Barbell');
    expect(choices.single.catalog, isNull);
    expect(choices.single.isCustom, isFalse);
  });

  test('custom exercises are marked', () {
    final choices = buildExerciseChoices(
      local: [local('custom-1', 'Sled push', builtIn: false)],
      catalog: snapshotOf([cat('builtin.v1.row', 'Barbell row')]),
    );
    expect(choices.firstWhere((c) => c.id == 'custom-1').isCustom, isTrue);
    expect(
      choices.firstWhere((c) => c.id == 'builtin.v1.row').isCustom,
      isFalse,
    );
  });

  test('archived local hidden', () {
    final choices = buildExerciseChoices(
      local: [local('custom-1', 'Old', builtIn: false, archivedAtMs: 5)],
    );
    expect(choices, isEmpty);
  });

  test('retired catalogue exercise still shown when local exists', () {
    final choices = buildExerciseChoices(
      local: [local('builtin.v1.old', 'Old lift')],
      catalog: snapshotOf([cat('builtin.v1.old', 'Old lift', retired: true)]),
    );
    expect(choices.single.id, 'builtin.v1.old');
    expect(choices.single.local, isNotNull);
    expect(choices.single.catalog, isNull);
  });

  test('retired catalogue exercise is hidden when not local', () {
    final choices = buildExerciseChoices(
      local: const [],
      catalog: snapshotOf([cat('builtin.v1.old', 'Old lift', retired: true)]),
    );
    expect(choices, isEmpty);
  });

  test('sorted by name case-insensitively', () {
    final choices = buildExerciseChoices(
      local: [local('custom-1', 'bicep curl variation', builtIn: false)],
      catalog: snapshotOf([
        cat('builtin.v1.b', 'Zottman curl'),
        cat('builtin.v1.a', 'Arnold press'),
      ]),
    );
    expect(choices.map((c) => c.name), [
      'Arnold press',
      'bicep curl variation',
      'Zottman curl',
    ]);
  });

  test('alias search finds RDL', () {
    final choices = buildExerciseChoices(
      local: const [],
      catalog: snapshotOf([
        cat('builtin.v1.rdl', 'Romanian deadlift', aliases: ['RDL']),
        cat('builtin.v1.row', 'Barbell row'),
      ]),
    );
    final hits = choices.where((c) => matchesExerciseQuery(c, 'rdl'));
    expect(hits.map((c) => c.id), ['builtin.v1.rdl']);
    final rdl = choices.firstWhere((c) => c.id == 'builtin.v1.rdl');
    expect(matchesExerciseQuery(rdl, ''), isTrue);
    expect(matchesExerciseQuery(rdl, '  RDL '), isTrue);
  });

  test('query matches muscle group and equipment', () {
    final choice = buildExerciseChoices(
      local: const [],
      catalog: snapshotOf([
        cat(
          'builtin.v1.pu',
          'Pull-up',
          group: 'Back',
          equipment: const ['pull_up_bar'],
        ),
      ]),
    ).single;
    expect(matchesExerciseQuery(choice, 'back'), isTrue);
    expect(matchesExerciseQuery(choice, 'pull-up bar'), isTrue);
    expect(matchesExerciseQuery(choice, 'kettlebell'), isFalse);
  });

  test('equipment labels', () {
    expect(equipmentLabel(['barbell', 'bench']), 'Barbell, Bench');
    expect(equipmentLabel(['pull_up_bar']), 'Pull-up bar');
    expect(equipmentLabel(['ez_bar', 'trap_bar']), 'EZ bar, Trap bar');
    expect(equipmentLabel(['bodyweight']), 'Bodyweight');
    expect(equipmentLabel(['other']), 'Other');
    expect(equipmentLabel(const []), '');
    for (final entry in {
      'dumbbell': 'Dumbbell',
      'kettlebell': 'Kettlebell',
      'machine': 'Machine',
      'cable': 'Cable',
      'band': 'Band',
      'plate': 'Plate',
      'box': 'Box',
      'rings': 'Rings',
    }.entries) {
      expect(equipmentLabel([entry.key]), entry.value);
    }
  });
}
