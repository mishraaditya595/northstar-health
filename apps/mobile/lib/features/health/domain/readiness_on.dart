import 'health_types.dart';
import 'readiness.dart';
import 'sleep_nights.dart';
import 'sleep_score.dart';
import 'training_load.dart';

/// A range night's sleep score, the same on the sleep and readiness tabs:
/// earlier nights from [nights], its own window's heart rate and the latest
/// resting HR up to its date.
SleepScore? nightScoreOf(
  SleepNight n,
  List<SleepNight> nights,
  Map<DateTime, double> sleepHr,
  List<DayValue> restingHr,
) => scoreSleep(
  n,
  priorNights: [
    for (final p in nights)
      if (p.date.isBefore(n.date)) p,
  ],
  sleepAvgHr: sleepHr[n.date],
  restingHr: restingHr.where((d) => !d.day.isAfter(n.date)).lastOrNull?.value,
);

({DateTime day, ReadinessResult result}) readinessOn(
  DateTime day,
  Map<DateTime, SleepNight> byDate,
  List<SleepNight> nights,
  Map<DateTime, double> sleepHr,
  List<DayValue> restingHr,
  List<DayValue> hrvDaily,
  List<DayValue> rhrDaily,
  List<LoadSession> load,
) {
  final night = byDate[day];
  return (
    day: day,
    result: scoreReadiness(
      today: day,
      lastNight: night,
      sleepScore: night == null
          ? null
          : nightScoreOf(night, nights, sleepHr, restingHr),
      priorNights: [
        for (final n in nights)
          if (n.date.isBefore(day)) n,
      ],
      hrvDaily: hrvDaily,
      restingHrDaily: rhrDaily,
      loadSessions: load,
    ),
  );
}
