import 'package:flutter/material.dart';

import '../../../core/design/page_header.dart';
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

/// A workout row: a kit [NsListCard] and, for a workout from another app, its
/// source tag under the card (a trailing tag overflows at large text).
class WorkoutRowCard extends StatelessWidget {
  const WorkoutRowCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.source,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Shown as `From <source>`.
  final String? source;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      NsListCard(icon: icon, title: title, subtitle: subtitle, onTap: onTap),
      if (source != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 14),
          child: Row(children: [Flexible(child: NsTag('From $source'))]),
        ),
    ],
  );
}
