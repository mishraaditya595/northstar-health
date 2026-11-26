import '../../workouts/domain/workout_library_models.dart';
import '../../workouts/domain/durations.dart';
import 'catalog_models.dart';
import 'exercise_choices.dart';

/// Standalone, not retired templates the phone can show: every exercise is active in
/// [snapshot] and has a mode the logger can record. Sorted by name.
List<CatalogTemplate> browsableTemplates(CatalogSnapshot snapshot) {
  final byId = {for (final e in snapshot.activeExercises) e.id: e};
  final result = [
    for (final template in snapshot.templates)
      if (template.standalone &&
          !template.retired &&
          template.exercises.every(
            (row) => loggableModes.contains(byId[row.exerciseId]?.mode),
          ))
        template,
  ];
  result.sort((a, b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.id.compareTo(b.id);
  });
  return result;
}

/// "4 × 6–8 reps", "3 × 10 reps" or "3 × 45 s".
String prescriptionLabel(CatalogPrescription p) {
  final seconds = p.durationSeconds;
  if (seconds != null) return '${p.sets} × ${formatDurationSeconds(seconds)}';
  final low = p.repsMin!;
  final high = p.repsMax!;
  return '${p.sets} × ${low == high ? '$low' : '$low–$high'} reps';
}

/// "Rest 90 s" or "Rest 2 min 30 s"; under two minutes stays in seconds.
String restLabel(int seconds) {
  if (seconds == 0) return 'No rest';
  return 'Rest ${seconds < 120 ? '$seconds s' : formatDurationSeconds(seconds)}';
}

/// The rows of [template] with the catalogue exercise each one names, ready
/// for copying into a plan or starting a workout. Throws [StateError] when an
/// exercise is missing from [snapshot] (browsable templates never are).
List<TemplateRowInput> templateRowInputs(
  CatalogTemplate template,
  CatalogSnapshot snapshot,
) {
  final byId = {for (final e in snapshot.exercises) e.id: e};
  return [
    for (final row in template.exercises)
      (
        exercise: _definitionInput(
          byId[row.exerciseId] ??
              (throw StateError('Template exercise is missing')),
        ),
        sets: row.sets,
        repsMin: row.repsMin,
        repsMax: row.repsMax,
        durationSeconds: row.durationSeconds,
        restSeconds: row.restSeconds,
        note: row.note,
      ),
  ];
}

CatalogDefinitionInput _definitionInput(CatalogExercise e) => (
  id: e.id,
  name: e.name,
  muscleGroup: e.muscleGroup,
  equipment: equipmentLabel(e.equipment),
  category: categoryLabel(e.category),
  mode: e.mode,
  primaryMuscles: e.primaryMuscles,
  secondaryMuscles: e.secondaryMuscles,
);
