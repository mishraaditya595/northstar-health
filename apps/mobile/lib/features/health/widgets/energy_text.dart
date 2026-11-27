import '../domain/energy.dart';
import '../health_format.dart';

/// `Started today at 78 · down 16 since morning`.
String energyChangeText(Energy e) {
  final started = 'Started today at ${e.start} · ';
  final drop = e.start - e.value;
  if (drop == 0) return '${started}no change since morning';
  if (drop > 0) return '${started}down $drop since morning';
  return '${started}up ${-drop} since morning';
}

String _count(int n, String one, String many) =>
    '$n more ${n == 1 ? one : many}';

/// `Still learning your patterns: 12 more workouts for a calibrated score.`;
/// null when there is nothing left to learn.
String? energyLearningText(EnergyLearning l) {
  if (!l.show) return null;
  final workouts = (l.workoutsNeeded ?? 0) > 0
      ? _count(l.workoutsNeeded!, 'workout', 'workouts')
      : null;
  final days = l.daysNeeded == null
      ? null
      : '${_count(l.daysNeeded!, 'day', 'days')} of data';
  final what = [?workouts, ?days].join(' and ');
  return 'Still learning your patterns: $what for a calibrated score.';
}

/// `Workout at 7:10 AM`, `Active day so far`, `Awake 10 hours`,
/// `Nap at 2:40 PM (capped)`.
String energyItemLabel(EnergyItem i) {
  String time() => formatClockTime(i.at!.toLocal());
  return switch (i.kind) {
    EnergyItemKind.workout => 'Workout at ${time()}',
    EnergyItemKind.activeDay => 'Active day so far',
    EnergyItemKind.awake =>
      'Awake ${i.awakeHours} ${i.awakeHours == 1 ? 'hour' : 'hours'}',
    EnergyItemKind.nap => 'Nap at ${time()}${i.capped ? ' (capped)' : ''}',
  };
}

/// `−9` (U+2212) or `+3`.
String energyPointsText(int points) => points < 0 ? '−${-points}' : '+$points';

/// `Energy starts after 2 more days with data.`
String energyBuildingText(int days) =>
    'Energy starts after $days more ${days == 1 ? 'day' : 'days'} with data.';
