import '../../workouts/domain/workout_library_models.dart';
import 'catalog_models.dart';

const _equipmentLabels = {
  'barbell': 'Barbell',
  'dumbbell': 'Dumbbell',
  'kettlebell': 'Kettlebell',
  'machine': 'Machine',
  'cable': 'Cable',
  'band': 'Band',
  'bodyweight': 'Bodyweight',
  'bench': 'Bench',
  'pull_up_bar': 'Pull-up bar',
  'ez_bar': 'EZ bar',
  'trap_bar': 'Trap bar',
  'plate': 'Plate',
  'box': 'Box',
  'rings': 'Rings',
  'other': 'Other',
};

String equipmentLabel(List<String> equipment) =>
    equipment.map((id) => _equipmentLabels[id] ?? id).join(', ');

/// One pickable exercise: a catalogue exercise, a local built-in or a custom
/// exercise. [local] is the account's copy, null until first used.
class ExerciseChoice {
  const ExerciseChoice({
    required this.id,
    required this.name,
    required this.aliases,
    required this.muscleGroup,
    required this.equipment,
    required this.mode,
    required this.isCustom,
    this.catalog,
    this.local,
  });

  final String id;
  final String name;
  final List<String> aliases;
  final String muscleGroup;
  final String equipment;
  final String mode;
  final bool isCustom;
  final CatalogExercise? catalog;
  final ExerciseRecord? local;
}

List<ExerciseChoice> buildExerciseChoices({
  required List<ExerciseRecord> local,
  CatalogSnapshot? catalog,
}) {
  final localById = {
    for (final record in local)
      if (record.archivedAtMs == null) record.uuid: record,
  };
  final choices = <ExerciseChoice>[];
  final fromCatalog = <String>{};
  for (final exercise
      in catalog?.activeExercises ?? const <CatalogExercise>[]) {
    fromCatalog.add(exercise.id);
    choices.add(
      ExerciseChoice(
        id: exercise.id,
        name: exercise.name,
        aliases: exercise.aliases,
        muscleGroup: exercise.muscleGroup,
        equipment: equipmentLabel(exercise.equipment),
        mode: exercise.mode,
        isCustom: false,
        catalog: exercise,
        local: localById[exercise.id],
      ),
    );
  }
  for (final record in localById.values) {
    if (fromCatalog.contains(record.uuid)) continue;
    choices.add(
      ExerciseChoice(
        id: record.uuid,
        name: record.name,
        aliases: const [],
        muscleGroup: record.muscleGroup,
        equipment: record.equipment,
        mode: record.inputMode,
        isCustom: !record.isBuiltIn,
        local: record,
      ),
    );
  }
  choices.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return List.unmodifiable(choices);
}

bool matchesExerciseQuery(ExerciseChoice choice, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return [
    choice.name,
    ...choice.aliases,
    choice.muscleGroup,
    choice.equipment,
  ].any((field) => field.toLowerCase().contains(needle));
}
