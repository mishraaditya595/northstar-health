import 'health_types.dart';
import 'sleep_nights.dart';

/// Local date of a finished workout and its completed working sets (summed if
/// several that day).
typedef TrainingDay = ({DateTime day, int workingSets});

const _minSide = 3;
const _minSleepDifference = Duration(minutes: 20);
const _minRestingHrDifference = 2.0;

typedef _Ymd = (int, int, int);

_Ymd _ymd(DateTime d) => (d.year, d.month, d.day);
_Ymd _next(DateTime d) => _ymd(DateTime(d.year, d.month, d.day + 1));
_Ymd _previous(DateTime d) => _ymd(DateTime(d.year, d.month, d.day - 1));

class SleepAfterTraining {
  const SleepAfterTraining({
    required this.afterTraining,
    required this.otherNights,
    required this.trainingNights,
    required this.otherNightsCount,
  });

  final Duration afterTraining, otherNights;
  final int trainingNights, otherNightsCount;

  Duration get difference => afterTraining - otherNights;
}

SleepAfterTraining? sleepAfterTraining(
  List<SleepNight> nights,
  List<TrainingDay> training,
) {
  final trained = {for (final t in training) _ymd(t.day)};
  final after = <Duration>[];
  final other = <Duration>[];
  for (final n in nights) {
    (trained.contains(_previous(n.date)) ? after : other).add(n.asleep);
  }
  if (after.length < _minSide || other.length < _minSide) return null;
  final result = SleepAfterTraining(
    afterTraining: _meanDuration(after),
    otherNights: _meanDuration(other),
    trainingNights: after.length,
    otherNightsCount: other.length,
  );
  if (result.difference.abs() < _minSleepDifference) return null;
  return result;
}

Duration _meanDuration(List<Duration> v) => Duration(
  microseconds: v.fold<int>(0, (s, d) => s + d.inMicroseconds) ~/ v.length,
);

class RestingHrAfterHard {
  const RestingHrAfterHard({
    required this.afterHard,
    required this.otherDays,
    required this.hardDays,
    required this.otherDaysCount,
  });

  final double afterHard, otherDays;
  final int hardDays, otherDaysCount;

  double get difference => afterHard - otherDays;
}

RestingHrAfterHard? restingHrAfterHardSessions(
  List<DayValue> restingHr,
  List<TrainingDay> training,
) {
  final n = training.length;
  if (n < _minSide) return null;
  final sorted = [...training]
    ..sort((a, b) => b.workingSets.compareTo(a.workingSets));
  final k = ((n + 2) ~/ 3).clamp(1, n);
  final threshold = sorted[k - 1].workingSets;
  final mornings = {
    for (final t in training)
      if (t.workingSets >= threshold) _next(t.day),
  };

  final afterHard = <double>[];
  final other = <double>[];
  for (final v in restingHr) {
    final key = _ymd(v.day);
    if (mornings.contains(key)) {
      afterHard.add(v.value);
    } else {
      other.add(v.value);
    }
  }
  if (afterHard.length < _minSide || other.length < _minSide) return null;
  final result = RestingHrAfterHard(
    afterHard: _mean(afterHard),
    otherDays: _mean(other),
    hardDays: afterHard.length,
    otherDaysCount: other.length,
  );
  if (result.difference.abs() < _minRestingHrDifference) return null;
  return result;
}

double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
