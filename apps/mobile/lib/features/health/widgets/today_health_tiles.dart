import 'package:flutter/material.dart';

import '../../workouts/domain/workout_models.dart';
import '../application/health_overview.dart';
import '../domain/metric_explanations.dart';
import '../health_format.dart';

/// One tile of the Today health grid. A null [value] shows as a dash.
typedef TodayTile = ({
  String label,
  IconData icon,
  String? value,
  String? unit,
  String caption,
  MetricGap? gap,
  String? route,
  MetricKey? infoKey,
  MetricUsual? usual,
  bool sleepTint,
});

TodayTile _gapTile(
  String label,
  IconData icon,
  MetricGap gap,
  String noData, {
  MetricKey? infoKey,
  bool sleepTint = false,
}) => (
  label: label,
  icon: icon,
  value: null,
  unit: null,
  caption: switch (gap) {
    MetricGap.noData => noData,
    MetricGap.needsAccess => 'Allow more data',
    MetricGap.notAllowed => 'Not allowed · Manage',
    MetricGap.failed => "Couldn't read · Try again",
    MetricGap.unsupported => 'Not available on this device',
  },
  gap: gap,
  route: null,
  infoKey: infoKey,
  usual: null,
  sleepTint: sleepTint,
);

const _noSleep = 'No sleep recorded last night';
const _noSteps = 'No steps yet today';
const _noRestingHr = 'None in the last 30 days';

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

TodayTile sleepTile(HealthOverview o) {
  TodayTile gapOf(MetricGap g) => _gapTile(
    'Sleep',
    Icons.bedtime_outlined,
    g,
    _noSleep,
    infoKey: MetricKey.timeAsleep,
    sleepTint: true,
  );
  return switch (o.sleep) {
    SectionGap(gap: final g) => gapOf(g),
    SectionData(:final value) =>
      value.lastNight.date == _dayOf(o.readAt)
          ? (
              label: 'Sleep',
              icon: Icons.bedtime_outlined,
              value: formatDuration(value.lastNight.asleep),
              unit: null,
              caption: 'Ended ${formatClockTime(value.lastNight.end)}',
              gap: null,
              route: '/health/sleep',
              infoKey: MetricKey.timeAsleep,
              usual: null,
              sleepTint: true,
            )
          : gapOf(MetricGap.noData),
  };
}

TodayTile stepsTile(HealthOverview o) {
  TodayTile gap(MetricGap g) => _gapTile(
    'Steps',
    Icons.directions_walk,
    g,
    _noSteps,
    infoKey: MetricKey.steps,
  );
  return switch (o.activity) {
    SectionGap(gap: final g) => gap(g),
    SectionData(:final value) when value.stepsToday != null => (
      label: 'Steps',
      icon: Icons.directions_walk,
      value: formatCount(value.stepsToday!),
      unit: null,
      caption: 'As of ${formatClockTime(o.readAt)}',
      gap: null,
      route: '/health/activity',
      infoKey: MetricKey.steps,
      usual: dailyAverageFrom(value.stepsDaily, o.readAt),
      sleepTint: false,
    ),
    SectionData(value: ActivityOverview(stepsGap: final g?)) => gap(g),
    SectionData() => gap(MetricGap.noData),
  };
}

TodayTile restingHrTile(HealthOverview o) {
  TodayTile gap(MetricGap g) => _gapTile(
    'Resting HR',
    Icons.favorite_outline,
    g,
    _noRestingHr,
    infoKey: MetricKey.restingHeartRate,
  );
  return switch (o.heart) {
    SectionGap(gap: final g) => gap(g),
    SectionData(value: HeartOverview(restingHr: final hr?) && final heart) =>
      _restingHrData(o, heart, hr),
    SectionData(value: HeartOverview(restingHrGap: final g?)) => gap(g),
    SectionData() => gap(MetricGap.noData),
  };
}

TodayTile _restingHrData(
  HealthOverview o,
  HeartOverview heart,
  ({DateTime day, double value}) hr,
) {
  final today = _dayOf(o.readAt);
  final isToday = hr.day == today;
  final usual = usualFrom(heart.restingHrDaily, today, reading: hr);
  var caption = isToday ? 'Today' : formatHealthDate(hr.day);
  if (usual != null && isToday) {
    final exact = hr.value - (usual.low + usual.high) / 2;
    final diff = exact.round();
    caption +=
        ' · ${exact.abs() < 1
            ? 'about usual'
            : diff < 0
            ? '${-diff} below usual'
            : '$diff above usual'}';
  }
  return (
    label: 'Resting HR',
    icon: Icons.favorite_outline,
    value: '${hr.value.round()}',
    unit: 'bpm',
    caption: caption,
    gap: null,
    route: '/health/heart',
    infoKey: MetricKey.restingHeartRate,
    usual: usual,
    sleepTint: false,
  );
}

/// Finished BeyondRep sessions on the local day of [localNow]. A null
/// [completed] (history loading or failed) makes no claim about today.
TodayTile workoutsTile(
  List<WorkoutSessionRecord>? completed,
  DateTime localNow,
) {
  if (completed == null) {
    return (
      label: 'Workouts',
      icon: Icons.fitness_center,
      value: '—',
      unit: null,
      caption: 'Finished today',
      gap: null,
      route: '/progress',
      infoKey: null,
      usual: null,
      sleepTint: false,
    );
  }
  bool today(DateTime t) {
    final local = t.toLocal();
    return local.year == localNow.year &&
        local.month == localNow.month &&
        local.day == localNow.day;
  }

  final sessions = [
    for (final s in completed)
      if (s.status == WorkoutStatus.completed &&
          s.completedAtUtc != null &&
          today(s.completedAtUtc!))
        s,
  ]..sort((a, b) => a.startedAtUtc.compareTo(b.startedAtUtc));
  if (sessions.isEmpty) {
    return (
      label: 'Workouts',
      icon: Icons.fitness_center,
      value: '—',
      unit: null,
      caption: 'None yet today',
      gap: null,
      route: '/progress',
      infoKey: null,
      usual: null,
      sleepTint: false,
    );
  }
  final first = sessions.first;
  final minutes =
      (first.completedAtUtc!.difference(first.startedAtUtc)).inSeconds / 60;
  return (
    label: 'Workouts',
    icon: Icons.fitness_center,
    value: '${sessions.length}',
    unit: 'today',
    caption: '${first.name} · ${minutes.round()} min',
    gap: null,
    route: '/progress',
    infoKey: null,
    usual: null,
    sleepTint: false,
  );
}
