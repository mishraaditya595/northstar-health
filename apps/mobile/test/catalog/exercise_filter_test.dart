import 'package:beyondrep/features/catalog/domain/exercise_choices.dart';
import 'package:beyondrep/features/catalog/domain/exercise_filter.dart';
import 'package:flutter_test/flutter_test.dart';

ExerciseChoice choice(
  String name, {
  String group = 'Legs',
  String equipment = 'Barbell',
  List<String> primary = const ['quads'],
  bool custom = false,
}) => ExerciseChoice(
  id: name,
  name: name,
  aliases: const [],
  muscleGroup: group,
  equipment: equipment,
  mode: 'reps_load',
  isCustom: custom,
  primaryMuscles: primary,
);

void main() {
  final all = [
    choice('Dumbbell lunge', equipment: 'Dumbbell'),
    choice('Back squat'),
    choice('Dumbbell row', group: 'Back', equipment: 'Dumbbell, Bench'),
    choice('Romanian deadlift', primary: const ['hamstrings', 'glutes']),
    choice('Sled push', group: 'legs', equipment: 'Sled', custom: true),
  ];

  test('no filter matches everything', () {
    expect(all.every(const ExerciseFilter().matches), isTrue);
  });

  test('group compares ignoring case and includes custom exercises', () {
    final names = all
        .where(const ExerciseFilter(group: 'Legs').matches)
        .map((c) => c.name);
    expect(names, [
      'Dumbbell lunge',
      'Back squat',
      'Romanian deadlift',
      'Sled push',
    ]);
  });

  test('equipment matches one label of a comma separated list', () {
    final names = all
        .where(const ExerciseFilter(equipment: 'Bench').matches)
        .map((c) => c.name);
    expect(names, ['Dumbbell row']);
    expect(const ExerciseFilter(equipment: 'Bench').matches(all[1]), isFalse);
  });

  test('group, equipment and query combine', () {
    const filter = ExerciseFilter(group: 'Legs', equipment: 'Dumbbell');
    final names = all
        .where((c) => filter.matches(c) && matchesExerciseQuery(c, 'lunge'))
        .map((c) => c.name);
    expect(names, ['Dumbbell lunge']);
  });

  test('query finds an exercise by its primary muscle name', () {
    final hits = all
        .where((c) => matchesExerciseQuery(c, 'hamstrings'))
        .map((c) => c.name);
    expect(hits, ['Romanian deadlift']);
    expect(matchesExerciseQuery(all[0], 'hamstrings'), isFalse);
  });

  test('equipmentOptions are distinct and sorted', () {
    expect(equipmentOptions(all), ['Barbell', 'Bench', 'Dumbbell', 'Sled']);
    expect(equipmentOptions(const []), isEmpty);
  });
}
