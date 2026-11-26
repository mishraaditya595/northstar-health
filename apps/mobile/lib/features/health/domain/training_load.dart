import '../../workouts/domain/workout_models.dart';
import 'daily_series.dart';
import 'outside_workouts.dart';

typedef LoadSession = ({DateTime start, double minutes, double intensity});

/// Effort assumed when no set of a BeyondRep session has an RPE.
const _unratedIntensity = 0.8;

/// Effort assumed for workouts from other apps: there is no reliable
/// maximum heart rate without an age.
const _outsideIntensity = 0.7;

const _acuteDays = 7;
const _chronicDays = 28;
const _minHistoryDays = 14;

double _intensityOf(WorkoutSessionRecord session) {
  final rpes = [
    for (final s in session.sets)
      if (s.status == WorkoutSetStatus.completed &&
          s.kind == WorkoutSetKind.working &&
          s.rpe != null)
        s.rpe!,
  ];
  if (rpes.isEmpty) return _unratedIntensity;
  return rpes.fold(0.0, (a, b) => a + b) / rpes.length / 10;
}

/// Completed BeyondRep sessions plus outside workouts that did not merge
/// into one; merged outside workouts are not counted twice.
List<LoadSession> loadSessions(
  List<WorkoutSessionRecord> sessions,
  WorkoutMerge merge,
) => [
  for (final s in sessions)
    if (s.status == WorkoutStatus.completed && s.completedAtUtc != null)
      (
        start: s.startedAtUtc,
        minutes: s.completedAtUtc!.difference(s.startedAtUtc).inSeconds / 60,
        intensity: _intensityOf(s),
      ),
  for (final w in merge.standalone)
    (
      start: w.start,
      minutes: w.end.difference(w.start).inSeconds / 60,
      intensity: _outsideIntensity,
    ),
];

int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

double _scoreOf(double r) {
  if (r <= 0.8) return 90;
  if (r <= 1.3) return 90 - (r - 0.8) / 0.5 * 20;
  if (r <= 1.8) return 70 - (r - 1.3) / 0.5 * 40;
  return 30;
}

/// Last 7 days' average daily load against the last 28 days', [today]
/// excluded; null with under 14 days of history or no load in 28 days.
({double ratio, double score})? trainingLoadOf(
  List<LoadSession> sessions,
  DateTime today,
) {
  final day = dayOf(today);
  var acute = 0.0;
  var chronic = 0.0;
  int? oldest;
  for (final s in sessions) {
    final ago = _daysBetween(s.start.toLocal(), day);
    if (ago < 1 || ago > _chronicDays) continue;
    final load = s.minutes * s.intensity;
    chronic += load;
    if (ago <= _acuteDays) acute += load;
    if (oldest == null || ago > oldest) oldest = ago;
  }
  if (oldest == null || oldest < _minHistoryDays || chronic <= 0) return null;
  final ratio = (acute / _acuteDays) / (chronic / _chronicDays);
  return (ratio: ratio, score: _scoreOf(ratio));
}
