import 'catalog_models.dart';
import 'exercise_choices.dart';

/// Programs the phone can show: every template the week uses is fully
/// loggable with active exercises. Program-only templates count. Sorted by
/// days per week, then name.
List<CatalogProgram> browsablePrograms(CatalogSnapshot snapshot) {
  final byId = {for (final e in snapshot.activeExercises) e.id: e};
  final templates = {for (final t in snapshot.templates) t.id: t};
  bool loggable(String id) {
    final template = templates[id];
    return template != null &&
        template.exercises.every(
          (row) => loggableModes.contains(byId[row.exerciseId]?.mode),
        );
  }

  final result = [
    for (final program in snapshot.programs)
      if (program.week.whereType<String>().every(loggable)) program,
  ];
  result.sort((a, b) {
    final byDays = a.daysPerWeek.compareTo(b.daysPerWeek);
    if (byDays != 0) return byDays;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.id.compareTo(b.id);
  });
  return result;
}

/// Any template, including program-only ones, for the program preview.
CatalogTemplate? programTemplate(CatalogSnapshot snapshot, String id) {
  for (final template in snapshot.templates) {
    if (template.id == id) return template;
  }
  return null;
}
