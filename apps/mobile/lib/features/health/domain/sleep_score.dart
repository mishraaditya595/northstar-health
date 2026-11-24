import 'sleep_nights.dart';

enum SleepContributor {
  duration,
  deep,
  rem,
  efficiency,
  timing,
  sleepHeartRate,
}

enum ContributorRating { good, fair, poor }

class ContributorResult {
  const ContributorResult(this.score, this.rating);

  /// 0..1.
  final double score;
  final ContributorRating rating;
}

class SleepScore {
  const SleepScore({required this.value, required this.contributors});

  /// 0..100.
  final int value;
  final Map<SleepContributor, ContributorResult> contributors;
}

const _weights = {
  SleepContributor.duration: 35,
  SleepContributor.deep: 15,
  SleepContributor.rem: 15,
  SleepContributor.efficiency: 15,
  SleepContributor.timing: 10,
  SleepContributor.sleepHeartRate: 10,
};

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

ContributorResult _result(double score) => ContributorResult(
  score,
  score >= 0.8
      ? ContributorRating.good
      : score >= 0.5
      ? ContributorRating.fair
      : ContributorRating.poor,
);

double _share(double s, double low) {
  if (s >= low && s <= 0.25) return 1;
  if (s < low) return s / low;
  return _clamp01(1 - (s - 0.25) / 0.15);
}

/// Minutes after 12:00 local, so evening and after-midnight starts are close.
int _minutesAfterNoon(DateTime t) {
  final l = t.toLocal();
  return (l.hour * 60 + l.minute - 720) % 1440;
}

double? _timing(SleepNight night, List<SleepNight> priorNights) {
  final recent = [...priorNights]..sort((a, b) => b.date.compareTo(a.date));
  final starts = [for (final n in recent.take(14)) _minutesAfterNoon(n.start)]
    ..sort();
  if (starts.length < 5) return null;
  final mid = starts.length ~/ 2;
  final median = starts.length.isOdd
      ? starts[mid].toDouble()
      : (starts[mid - 1] + starts[mid]) / 2;
  final d = (_minutesAfterNoon(night.start) - median).abs();
  return _clamp01((120 - d) / 90);
}

/// On-device sleep score, or null when the night has no sleep stages.
SleepScore? scoreSleep(
  SleepNight night, {
  List<SleepNight> priorNights = const [],
  double? sleepAvgHr,
  double? restingHr,
}) {
  if (!night.hasStages) return null;
  final m = night.asleep.inMinutes;
  final asleep = night.asleep.inSeconds;
  final inBed = (night.inBed ?? night.span).inSeconds;
  final timing = _timing(night, priorNights);
  final scores = <SleepContributor, double>{
    SleepContributor.duration: _clamp01((m - 240) / 210),
    SleepContributor.deep: _share(night.deep.inSeconds / asleep, 0.15),
    SleepContributor.rem: _share(night.rem.inSeconds / asleep, 0.20),
    SleepContributor.efficiency: _clamp01((asleep / inBed - 0.70) / 0.20),
    SleepContributor.timing: ?timing,
    if (sleepAvgHr != null && restingHr != null)
      SleepContributor.sleepHeartRate: _clamp01(
        1 - (sleepAvgHr - restingHr) / 10,
      ),
  };
  var sum = 0.0;
  var weights = 0;
  for (final e in scores.entries) {
    sum += _weights[e.key]! * e.value;
    weights += _weights[e.key]!;
  }
  return SleepScore(
    value: (100 * sum / weights).round(),
    contributors: {for (final e in scores.entries) e.key: _result(e.value)},
  );
}
