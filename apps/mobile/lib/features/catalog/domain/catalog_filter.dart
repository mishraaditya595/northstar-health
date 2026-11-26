import 'catalog_models.dart';

/// Goals in the order the filter sheet lists them.
const catalogGoals = [
  'strength',
  'hypertrophy',
  'general',
  'endurance',
  'fat_loss',
];

const _goalLabels = {
  'strength': 'Strength',
  'hypertrophy': 'Hypertrophy',
  'general': 'General fitness',
  'endurance': 'Endurance',
  'fat_loss': 'Fat loss',
};

String goalLabel(String goal) => _goalLabels[goal] ?? goal;

/// Equipment that never needs to be selected: it is always available.
const _alwaysAvailable = 'bodyweight';

/// Narrowing for the Workouts and Programs lists. Not persisted.
///
/// [goals] is any-match, [equipment] is "what I have" (an item shows when
/// every piece it needs is selected, bodyweight is always available, none
/// selected means off) and [daysPerWeek] applies to programs only.
class CatalogFilter {
  const CatalogFilter({
    this.goals = const {},
    this.equipment = const {},
    this.daysPerWeek,
    this.level,
    this.query = '',
  });

  final Set<String> goals;
  final Set<String> equipment;
  final int? daysPerWeek;
  final String? level;

  /// Lower-case search text.
  final String query;

  /// True when nothing at all narrows the list, search and level included.
  bool get isEmpty =>
      goals.isEmpty &&
      equipment.isEmpty &&
      daysPerWeek == null &&
      level == null &&
      query.isEmpty;

  /// How many of the sheet's filters are on: goal, equipment and days per
  /// week count once each. The level chips and search box are visible
  /// controls of their own and are not counted.
  int get activeCount =>
      (goals.isEmpty ? 0 : 1) +
      (equipment.isEmpty ? 0 : 1) +
      (daysPerWeek == null ? 0 : 1);

  CatalogFilter _copy({
    Set<String>? goals,
    Set<String>? equipment,
    int? Function()? daysPerWeek,
    String? Function()? level,
    String? query,
  }) => CatalogFilter(
    goals: goals ?? this.goals,
    equipment: equipment ?? this.equipment,
    daysPerWeek: daysPerWeek == null ? this.daysPerWeek : daysPerWeek(),
    level: level == null ? this.level : level(),
    query: query ?? this.query,
  );

  CatalogFilter toggleGoal(String goal) => _copy(goals: _toggled(goals, goal));

  CatalogFilter toggleEquipment(String id) =>
      _copy(equipment: _toggled(equipment, id));

  /// Selects [days], or clears it when it is already selected or null.
  CatalogFilter withDays(int? days) =>
      _copy(daysPerWeek: () => days == daysPerWeek ? null : days);

  CatalogFilter withLevel(String? level) => _copy(level: () => level);

  CatalogFilter withQuery(String query) => _copy(query: query);

  /// Goal, equipment and days per week off; level and search stay.
  CatalogFilter clearedSheetFilters() =>
      _copy(goals: const {}, equipment: const {}, daysPerWeek: () => null);
}

Set<String> _toggled(Set<String> set, String value) => set.contains(value)
    ? (Set.of(set)..remove(value))
    : (Set.of(set)..add(value));

bool _commonMatch(
  CatalogFilter filter, {
  required String name,
  required String description,
  required String level,
  required List<String> goals,
  required List<String> equipment,
}) {
  if (filter.level != null && level != filter.level) return false;
  if (filter.query.isNotEmpty &&
      !name.toLowerCase().contains(filter.query) &&
      !description.toLowerCase().contains(filter.query)) {
    return false;
  }
  if (filter.goals.isNotEmpty && !goals.any(filter.goals.contains)) {
    return false;
  }
  if (filter.equipment.isNotEmpty &&
      !equipment.every(
        (id) => id == _alwaysAvailable || filter.equipment.contains(id),
      )) {
    return false;
  }
  return true;
}

bool matchesTemplate(CatalogTemplate template, CatalogFilter filter) =>
    _commonMatch(
      filter,
      name: template.name,
      description: template.description,
      level: template.level,
      goals: template.goals,
      equipment: template.equipment,
    );

bool matchesProgram(CatalogProgram program, CatalogFilter filter) =>
    _commonMatch(
      filter,
      name: program.name,
      description: program.description,
      level: program.level,
      goals: program.goals,
      equipment: program.equipment,
    ) &&
    (filter.daysPerWeek == null || program.daysPerWeek == filter.daysPerWeek);

/// The goals present in [goalLists], in sheet order.
List<String> goalOptions(Iterable<List<String>> goalLists) {
  final present = {for (final list in goalLists) ...list};
  return [
    for (final goal in catalogGoals)
      if (present.contains(goal)) goal,
    ...(present.difference(catalogGoals.toSet()).toList()..sort()),
  ];
}

/// The equipment ids present in [equipmentLists] that a user has to pick:
/// bodyweight is left out because it always counts as available.
List<String> equipmentFilterOptions(Iterable<List<String>> equipmentLists) => ({
  for (final list in equipmentLists) ...list,
}..remove(_alwaysAvailable)).toList()..sort();
