/// The 14 muscle names shared by the catalogue, the cloud workout payload and
/// the body map (the `Muscle` enum names). Exact, case-sensitive strings.
const muscleVocabulary = <String>{
  'chest',
  'shoulders',
  'biceps',
  'forearms',
  'abs',
  'obliques',
  'quads',
  'calves',
  'traps',
  'lats',
  'lowerBack',
  'triceps',
  'glutes',
  'hamstrings',
};

const _displayNames = {
  'chest': 'Chest',
  'shoulders': 'Shoulders',
  'biceps': 'Biceps',
  'forearms': 'Forearms',
  'abs': 'Abs',
  'obliques': 'Obliques',
  'quads': 'Quads',
  'calves': 'Calves',
  'traps': 'Traps',
  'lats': 'Lats',
  'lowerBack': 'Lower back',
  'triceps': 'Triceps',
  'glutes': 'Glutes',
  'hamstrings': 'Hamstrings',
};

/// Reader-facing name of a muscle; an unknown name is returned unchanged.
String muscleDisplayName(String name) => _displayNames[name] ?? name;

/// The lists in their given order when they satisfy the cloud contract, else
/// null: every name in [muscleVocabulary], no duplicates within a list, no
/// muscle in both lists, at most 14 per list, and a non-empty primary list
/// whenever the secondary list is non-empty.
({List<String> primary, List<String> secondary})? validMuscles(
  List<String> primary,
  List<String> secondary,
) {
  bool listOk(List<String> list) =>
      list.length <= muscleVocabulary.length &&
      list.every(muscleVocabulary.contains) &&
      list.toSet().length == list.length;
  if (!listOk(primary) || !listOk(secondary)) return null;
  if (secondary.isNotEmpty && primary.isEmpty) return null;
  if (primary.any(secondary.contains)) return null;
  return (primary: primary, secondary: secondary);
}
