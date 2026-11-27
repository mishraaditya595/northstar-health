import '../../workouts/domain/workout_models.dart';
import 'energy_day.dart';
import 'energy_tuning.dart';
import 'health_types.dart';
import 'readiness.dart';
import 'training_load.dart';

/// Points lost per load unit (minutes x intensity) of a workout.
const energyWorkoutPointsPerLoad = 0.2;

/// Points lost per kcal of active energy above the usual, at most
/// [energyActiveMaxPoints].
const energyActivePointsPerKcal = 0.025;
const energyActiveMaxPoints = 15.0;

/// Points regained per nap minute; all naps together give at most
/// [energyNapMaxPoints] (and never more than what was drained).
const energyNapPointsPerMinute = 0.2;
const energyNapMaxPoints = 10.0;

/// Learning note: a calibrated score needs this many completed sessions in
/// the last [energyLearningWindowDays] days and this many baseline days.
const energyCalibratedSessions = 20;
const energyCalibratedBaselineDays = 14;
const energyLearningWindowDays = 90;

enum EnergyItemKind { workout, activeDay, awake, nap }

class EnergyItem {
  const EnergyItem({
    required this.kind,
    required this.points,
    this.at,
    this.awakeHours,
    this.capped = false,
  });

  final EnergyItemKind kind;

  /// Signed: drains are negative.
  final int points;

  /// Workout start or nap start, as given.
  final DateTime? at;

  /// Whole hours awake, for [EnergyItemKind.awake].
  final int? awakeHours;
  final bool capped;
}

class Energy {
  const Energy({
    required this.value,
    required this.band,
    required this.start,
    required this.items,
    this.awakeWaived = false,
    this.tuned = false,
  });

  final int value;
  final ReadinessBand band;
  final int start;
  final List<EnergyItem> items;

  /// The awake dip would have applied but this is a usual training hour.
  final bool awakeWaived;

  /// The personal drain multiplier is calibrated and not 1.0.
  final bool tuned;
}

/// Rounds [parts] to integers whose sum is the rounded sum of [parts]
/// (largest remainder; ties go to the earlier index).
List<int> apportion(List<double> parts) {
  final result = [for (final p in parts) p.floor()];
  if (parts.isEmpty) return result;
  var total = 0.0;
  for (final p in parts) {
    total += p;
  }
  var missing = total.round() - result.fold<int>(0, (a, b) => a + b);
  final order = List<int>.generate(parts.length, (i) => i)
    ..sort((a, b) {
      final c = (parts[b] - parts[b].floor()).compareTo(
        parts[a] - parts[a].floor(),
      );
      return c != 0 ? c : a.compareTo(b);
    });
  for (var k = 0; missing > 0; k = (k + 1) % order.length, missing--) {
    result[order[k]]++;
  }
  return result;
}

typedef _Raw = ({
  EnergyItemKind kind,
  double points,
  DateTime? at,
  int? awakeHours,
  bool capped,
});

Energy energyNow({
  required Readiness start,
  required WakingDay day,
  required DateTime now,
  required List<LoadSession> sessions,
  required List<HealthSample> hourlyActiveEnergy,
  required List<SleepSegment> sleepSegments,
  EnergyTuning tuning = EnergyTuning.generic,
}) {
  final multiplier = tuning.drainMultiplier;
  final raws = <_Raw>[];

  final counted = [
    for (final s in sessions)
      if (loadSessionEnd(s).isAfter(day.wake) &&
          !loadSessionEnd(s).isAfter(now))
        s,
  ]..sort((a, b) => a.start.compareTo(b.start));
  for (final s in counted) {
    raws.add((
      kind: EnergyItemKind.workout,
      points:
          -(s.minutes * s.intensity * energyWorkoutPointsPerLoad * multiplier),
      at: s.start,
      awakeHours: null,
      capped: false,
    ));
  }

  final excess = activeExcessKcal(
    hourlyActiveEnergy,
    day: day,
    now: now,
    workouts: counted,
  );
  if (excess != null) {
    final points = excess * energyActivePointsPerKcal * multiplier;
    raws.add((
      kind: EnergyItemKind.activeDay,
      points: -(points > energyActiveMaxPoints
          ? energyActiveMaxPoints
          : points),
      at: null,
      awakeHours: null,
      capped: false,
    ));
  }

  final awake = now.difference(day.wake);
  final dip = awakeDipPoints(awake);
  final waived = dip > 0 && tuning.usualHours.contains(now.hour);
  raws.add((
    kind: EnergyItemKind.awake,
    points: waived ? 0 : -dip,
    at: null,
    awakeHours: awake.inHours,
    capped: false,
  ));

  var drain = 0.0;
  for (final r in raws) {
    drain -= r.points;
  }
  final naps = napsIn(sleepSegments, wake: day.wake, now: now);
  final credit = [for (final n in naps) n.minutes * energyNapPointsPerMinute];
  final recharge = credit.fold<double>(0, (a, b) => a + b);
  final cap = drain < energyNapMaxPoints ? drain : energyNapMaxPoints;
  final capped = recharge > cap;
  final scale = capped ? cap / recharge : 1.0;
  for (var i = 0; i < naps.length; i++) {
    raws.add((
      kind: EnergyItemKind.nap,
      points: credit[i] * scale,
      at: naps[i].start,
      awakeHours: null,
      capped: capped,
    ));
  }

  // Missing is never zero: exact zeros take no part.
  final used = [
    for (final r in raws)
      if (r.points != 0) r,
  ];
  final points = apportion([for (final r in used) r.points]);
  final items = <EnergyItem>[
    for (var i = 0; i < used.length; i++)
      if (points[i] != 0)
        EnergyItem(
          kind: used[i].kind,
          points: points[i],
          at: used[i].at,
          awakeHours: used[i].awakeHours,
          capped: used[i].capped,
        ),
  ];
  final sum = items.fold<int>(0, (a, i) => a + i.points);
  final value = (start.value + sum).clamp(0, 100);
  return Energy(
    value: value,
    band: readinessBandOf(value),
    start: start.value,
    items: items,
    awakeWaived: waived,
    tuned: tuning.calibrated && multiplier != 1.0,
  );
}

class EnergyLearning {
  const EnergyLearning({this.workoutsNeeded, this.daysNeeded});

  final int? workoutsNeeded;
  final int? daysNeeded;

  bool get show => (workoutsNeeded ?? 0) > 0 || daysNeeded != null;
}

EnergyLearning energyLearningOf({
  required int? completedSessions,
  required int? baselineDays,
}) {
  final workouts = completedSessions == null
      ? null
      : (energyCalibratedSessions - completedSessions).clamp(
          0,
          energyCalibratedSessions,
        );
  final days =
      baselineDays != null && baselineDays < energyCalibratedBaselineDays
      ? energyCalibratedBaselineDays - baselineDays
      : null;
  return EnergyLearning(workoutsNeeded: workouts, daysNeeded: days);
}

/// Completed BeyondRep sessions in the [energyLearningWindowDays] days up to
/// [now].
int completedSessionsWithin(List<WorkoutSessionRecord> sessions, DateTime now) {
  final from = now.subtract(const Duration(days: energyLearningWindowDays));
  var n = 0;
  for (final s in sessions) {
    final done = s.completedAtUtc;
    if (s.status == WorkoutStatus.completed &&
        done != null &&
        done.isAfter(from) &&
        !done.isAfter(now)) {
      n++;
    }
  }
  return n;
}
