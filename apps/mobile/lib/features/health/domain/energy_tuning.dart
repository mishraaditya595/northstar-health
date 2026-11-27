import 'dart:math' as math;

import '../../workouts/domain/workout_models.dart';
import 'energy.dart';
import 'energy_day.dart';
import 'readiness.dart';
import 'sleep_nights.dart';
import 'training_load.dart';

/// Usual training hours need this many sessions, and an hour is usual when
/// the sessions starting in it or the hours beside it number at least
/// [energyUsualHourMinCount] and [energyUsualHourMinShare] of all sessions.
const energyUsualHoursMinSessions = 8;
const energyUsualHourMinCount = 3;
const energyUsualHourMinShare = 0.25;

/// Days of sleep, HRV and resting heart rate read for the tuning.
const energyHistoryDays = 120;

/// A session's norm is its exercise's volume in up to [energyNormSessions]
/// earlier sessions, needing at least [energyNormMinSessions].
const energyNormSessions = 5;
const energyNormMinSessions = 2;

/// Ratio change per RPE point above the norm's, for at most
/// [energyRpeMaxDiff] points.
const energyRpeWeight = 0.05;
const energyRpeMaxDiff = 3.0;

const energyTuneMinPairs = 10;
const energyTuneMinSpread = 10.0;
const energyExpectedLowRatio = 0.95;
const energyTuneGain = 8.0;
const energyDrainMultiplierFloor = 0.6;
const energyDrainMultiplierCeiling = 1.4;

/// What was learned about one person; lives in memory only.
class EnergyTuning {
  const EnergyTuning({
    required this.usualHours,
    required this.drainMultiplier,
    required this.calibrated,
  });

  /// Local clock hours (0-23) in which time awake costs nothing.
  final Set<int> usualHours;
  final double drainMultiplier;
  final bool calibrated;

  static const generic = EnergyTuning(
    usualHours: {},
    drainMultiplier: 1.0,
    calibrated: false,
  );
}

/// Local hours the [sessions] (already filtered) usually start around.
Set<int> usualTrainingHours(List<WorkoutSessionRecord> sessions) {
  final n = sessions.length;
  if (n < energyUsualHoursMinSessions) return {};
  final counts = List<int>.filled(24, 0);
  for (final s in sessions) {
    counts[s.startedAtUtc.toLocal().hour]++;
  }
  final need = math.max(
    energyUsualHourMinCount,
    (energyUsualHourMinShare * n).ceil(),
  );
  return {
    for (var h = 0; h < 24; h++)
      if (counts[(h + 23) % 24] + counts[h] + counts[(h + 1) % 24] >= need) h,
  };
}

String _exerciseKey(WorkoutSessionRecord s, String exerciseUuid) {
  for (final e in s.exercises) {
    if (e.uuid == exerciseUuid) {
      return e.definitionUuid ?? e.nameSnapshot.toLowerCase();
    }
  }
  return exerciseUuid;
}

bool _worked(WorkoutSetRecord s) =>
    s.status == WorkoutSetStatus.completed && s.kind == WorkoutSetKind.working;

/// Volume per exercise over completed working sets: kg x reps when any set
/// has both, else reps, else seconds. Exercises without volume are left out.
Map<String, double> _volumes(WorkoutSessionRecord s) {
  final byKey = <String, List<WorkoutSetRecord>>{};
  for (final set in s.sets) {
    if (_worked(set)) {
      byKey.putIfAbsent(_exerciseKey(s, set.exerciseUuid), () => []).add(set);
    }
  }
  final result = <String, double>{};
  for (final entry in byKey.entries) {
    double sum(double Function(WorkoutSetRecord) f) =>
        entry.value.fold(0.0, (a, b) => a + f(b));
    bool loaded(WorkoutSetRecord x) =>
        (x.loadGrams ?? 0) > 0 && (x.reps ?? 0) > 0;
    final double v;
    if (entry.value.any(loaded)) {
      v = sum((x) => loaded(x) ? x.loadGrams! / 1000 * x.reps! : 0);
    } else if (entry.value.any((x) => (x.reps ?? 0) > 0)) {
      v = sum((x) => (x.reps ?? 0).toDouble());
    } else {
      v = sum((x) => (x.durationSeconds ?? 0).toDouble());
    }
    if (v > 0) result[entry.key] = v;
  }
  return result;
}

double? _meanRpe(WorkoutSessionRecord s) {
  final rpes = [
    for (final x in s.sets)
      if (_worked(x) && x.rpe != null) x.rpe!,
  ];
  return _mean(rpes);
}

double? _mean(Iterable<double> v) {
  if (v.isEmpty) return null;
  return v.fold(0.0, (a, b) => a + b) / v.length;
}

/// How [s] went against what the person usually does in the same exercises
/// (1.0 is usual); null without a norm. [earlier] may hold any sessions, only
/// those starting before [s] count.
double? sessionPerformance(
  WorkoutSessionRecord s,
  List<WorkoutSessionRecord> earlier,
) {
  final volumes = _volumes(s);
  if (volumes.isEmpty) return null;
  final before = [
    for (final e in earlier)
      if (e.startedAtUtc.isBefore(s.startedAtUtc)) e,
  ]..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
  final earlierVolumes = {for (final e in before) e: _volumes(e)};
  final ratios = <double>[];
  final normSessions = <WorkoutSessionRecord>{};
  for (final entry in volumes.entries) {
    final used = <WorkoutSessionRecord>[];
    for (final e in before) {
      if (earlierVolumes[e]!.containsKey(entry.key)) used.add(e);
      if (used.length == energyNormSessions) break;
    }
    if (used.length < energyNormMinSessions) continue;
    final norm = _mean([for (final e in used) earlierVolumes[e]![entry.key]!]);
    if (norm == null || norm <= 0) continue;
    ratios.add(entry.value / norm);
    normSessions.addAll(used);
  }
  final ratio = _mean(ratios);
  if (ratio == null) return null;
  final rpe = _meanRpe(s);
  final normRpe = _mean([for (final e in normSessions) ?_meanRpe(e)]);
  if (rpe == null || normRpe == null) return ratio;
  final diff = (rpe - normRpe).clamp(-energyRpeMaxDiff, energyRpeMaxDiff);
  return ratio * (1 - energyRpeWeight * diff);
}

/// One bounded multiplier for what workouts and active calories cost:
/// above 1 when the person trains worse at lower energy than expected.
double drainMultiplierOf(
  List<({double energy, double ratio})> pairs, {
  required bool calibrated,
}) {
  if (!calibrated || pairs.length < energyTuneMinPairs) return 1.0;
  final sorted = [...pairs]..sort((a, b) => a.energy.compareTo(b.energy));
  final half = sorted.length ~/ 2;
  final lower = sorted.sublist(0, half);
  final upper = sorted.sublist(half);
  final lowEnergy = _mean([for (final p in lower) p.energy])!;
  final highEnergy = _mean([for (final p in upper) p.energy])!;
  if (highEnergy - lowEnergy < energyTuneMinSpread) return 1.0;
  final lowRatio = _mean([for (final p in lower) p.ratio])!;
  final highRatio = _mean([for (final p in upper) p.ratio])!;
  if (highRatio <= 0) return 1.0;
  final r = lowRatio / highRatio;
  final m = 1 + energyTuneGain * (energyExpectedLowRatio - r);
  if (m.isNaN) return 1.0;
  return m.clamp(energyDrainMultiplierFloor, energyDrainMultiplierCeiling);
}

/// Energy at the start of [session]: its waking day's start score less the
/// workouts of that day before it; null without a waking day or a ready
/// start. No active energy, awake dip or naps.
double? pastEnergyAt({
  required WorkoutSessionRecord session,
  required List<LoadSession> load,
  required List<SleepNight> nights,
  required ReadinessResult Function(DateTime day) readinessOnDay,
}) {
  final start = session.startedAtUtc.toLocal();
  final day = wakingDayOf(nights, start);
  if (day == null) return null;
  final result = readinessOnDay(day.day);
  if (result is! ReadinessReady) return null;
  var energy = result.readiness.value.toDouble();
  for (final l in load) {
    final end = loadSessionEnd(l);
    if (end.isAfter(day.wake) && !end.isAfter(start)) {
      energy -= l.minutes * l.intensity * energyWorkoutPointsPerLoad;
    }
  }
  return energy;
}

EnergyTuning energyTuningOf({
  required List<WorkoutSessionRecord> sessions,
  required List<LoadSession> load,
  required List<SleepNight> nights,
  required ReadinessResult Function(DateTime day) readinessOnDay,
  required WakingDay? currentDay,
  required DateTime now,
  required bool calibrated,
}) {
  final from = now.subtract(const Duration(days: energyLearningWindowDays));
  bool isCompleted(WorkoutSessionRecord s) =>
      s.status == WorkoutStatus.completed && s.completedAtUtc != null;
  final used = [
    for (final s in sessions)
      if (isCompleted(s) &&
          s.completedAtUtc!.isAfter(from) &&
          !s.completedAtUtc!.isAfter(now) &&
          (currentDay == null ||
              s.startedAtUtc.toLocal().isBefore(currentDay.wake)))
        s,
  ];
  final done = [
    for (final s in sessions)
      if (isCompleted(s)) s,
  ];
  final pairs = <({double energy, double ratio})>[];
  for (final s in used) {
    final energy = pastEnergyAt(
      session: s,
      load: load,
      nights: nights,
      readinessOnDay: readinessOnDay,
    );
    if (energy == null) continue;
    final ratio = sessionPerformance(s, done);
    if (ratio == null || !ratio.isFinite) continue;
    pairs.add((energy: energy, ratio: ratio));
  }
  return EnergyTuning(
    usualHours: usualTrainingHours(used),
    drainMultiplier: drainMultiplierOf(pairs, calibrated: calibrated),
    calibrated: calibrated,
  );
}
