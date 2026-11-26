import 'package:flutter/material.dart';

import '../domain/outside_workouts.dart';
import '../health_format.dart';

IconData outsideWorkoutIcon(OutsideWorkoutKind kind) => switch (kind) {
  OutsideWorkoutKind.strength => Icons.fitness_center,
  OutsideWorkoutKind.running => Icons.directions_run,
  OutsideWorkoutKind.walking || OutsideWorkoutKind.hiking => Icons.hiking,
  OutsideWorkoutKind.cycling => Icons.directions_bike,
  OutsideWorkoutKind.swimming => Icons.pool,
  OutsideWorkoutKind.rowing => Icons.rowing,
  OutsideWorkoutKind.yoga ||
  OutsideWorkoutKind.pilates => Icons.self_improvement,
  _ => Icons.sports_gymnastics,
};

/// `Today`, `Yesterday` or `24 Nov` for the local day of [at], against the
/// local day of [now].
String workoutDayLabel(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
  return switch (diff) {
    0 => 'Today',
    1 => 'Yesterday',
    _ => formatHealthDate(day),
  };
}

/// `Today 10:02 AM · 48 min`, local time.
String workoutWhen(DateTime startUtc, int minutes, DateTime now) {
  final local = startUtc.toLocal();
  return '${workoutDayLabel(local, now)} ${formatClockTime(local)} · $minutes min';
}
