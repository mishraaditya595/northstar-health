import 'exercise_choices.dart';

/// Muscle group and equipment narrowing for exercise lists. A null field
/// means "All".
class ExerciseFilter {
  const ExerciseFilter({this.group, this.equipment});

  final String? group;

  /// One equipment label, for example `Dumbbell`.
  final String? equipment;

  bool matches(ExerciseChoice c) {
    final group = this.group;
    if (group != null && c.muscleGroup.toLowerCase() != group.toLowerCase()) {
      return false;
    }
    final equipment = this.equipment;
    if (equipment == null) return true;
    final wanted = equipment.toLowerCase();
    return _labels(c.equipment).any((label) => label.toLowerCase() == wanted);
  }
}

List<String> _labels(String equipment) => equipment
    .split(',')
    .map((label) => label.trim())
    .where((label) => label.isNotEmpty)
    .toList();

/// The sorted, distinct equipment labels present in [all]. Labels that differ
/// only in case count as one; the first spelling seen is kept.
List<String> equipmentOptions(List<ExerciseChoice> all) {
  final byKey = <String, String>{};
  for (final c in all) {
    for (final label in _labels(c.equipment)) {
      byKey.putIfAbsent(label.toLowerCase(), () => label);
    }
  }
  return byKey.values.toList()..sort();
}
