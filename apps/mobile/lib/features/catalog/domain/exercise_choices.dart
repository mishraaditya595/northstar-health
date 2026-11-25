import '../../workouts/domain/muscles.dart';
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

const _categoryLabels = {
  'squat': 'Squat',
  'hinge': 'Hinge',
  'lunge': 'Lunge',
  'push_horizontal': 'Push',
  'push_vertical': 'Push',
  'pull_horizontal': 'Pull',
  'pull_vertical': 'Pull',
  'carry': 'Carry',
  'core': 'Core',
  'isolation': 'Isolation',
  'calf': 'Calf',
  'conditioning': 'Conditioning',
  'mobility': 'Mobility',
};

/// Display label stored as the local movement category, matching the labels
/// of the seeded exercises.
String categoryLabel(String category) => _categoryLabels[category] ?? category;

/// Input modes the logger can record today. Catalogue exercises in other
/// modes (`reps`, `duration_load`) are not offered until timed sets and
/// bodyweight logging exist, unless the account already has them locally.
const loggableModes = {'reps_load', 'duration'};

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
    this.primaryMuscles = const [],
    this.catalog,
    this.release,
    this.local,
  });

  final String id;
  final String name;
  final List<String> aliases;
  final String muscleGroup;
  final String equipment;
  final String mode;
  final bool isCustom;

  /// Primary muscle ids (for example `hamstrings`); empty for custom
  /// exercises. Used by search.
  final List<String> primaryMuscles;
  final CatalogExercise? catalog;

  /// Release of the snapshot [catalog] came from; null without a catalogue
  /// entry. Used when copying, so a refresh landing meanwhile cannot stamp a
  /// newer release on older data.
  final int? release;
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
    final record = localById[exercise.id];
    if (record == null && !loggableModes.contains(exercise.mode)) continue;
    choices.add(
      ExerciseChoice(
        id: exercise.id,
        name: exercise.name,
        aliases: exercise.aliases,
        muscleGroup: exercise.muscleGroup,
        equipment: equipmentLabel(exercise.equipment),
        mode: exercise.mode,
        isCustom: false,
        primaryMuscles: exercise.primaryMuscles,
        catalog: exercise,
        release: catalog!.release,
        local: record,
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
        primaryMuscles: record.primaryMuscles,
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
    ...choice.primaryMuscles.map(muscleDisplayName),
  ].any((field) => field.toLowerCase().contains(needle));
}
