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
    return equipment == null || _labels(c.equipment).contains(equipment);
  }
}

List<String> _labels(String equipment) => equipment
    .split(',')
    .map((label) => label.trim())
    .where((label) => label.isNotEmpty)
    .toList();

/// The sorted, distinct equipment labels present in [all].
List<String> equipmentOptions(List<ExerciseChoice> all) =>
    {for (final c in all) ..._labels(c.equipment)}.toList()..sort();
