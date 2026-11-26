import 'package:flutter/material.dart';

import '../../core/date_labels.dart';
import '../../core/design/hero_frame.dart';
import '../../core/design/page_header.dart';
import '../programs/application/program_providers.dart';
import '../programs/domain/program_status.dart';
import '../workouts/domain/workout_library_models.dart';

/// Rough length of a plan: each set takes its timed target or 40 s, plus the
/// plan's rest (90 s when none is set), rounded to 5 minutes, at least 5.
int estimatedPlanMinutes(WorkoutPlanRecord plan) {
  var seconds = 0;
  for (final row in plan.exercises) {
    seconds +=
        row.targetSets *
        ((row.targetDurationSeconds ?? 40) + (row.restSeconds ?? 90));
  }
  final rounded = (seconds / 60 / 5).round() * 5;
  return rounded < 5 ? 5 : rounded;
}

/// Today's hero for the active program: the workout with Start, "Rest day",
/// or "Done for today", with the next workout when there is nothing to start.
class TodayProgramHero extends StatelessWidget {
  const TodayProgramHero({
    required this.week,
    required this.onStart,
    required this.onOpenProgram,
    super.key,
  });

  final ProgramWeek week;
  final void Function(String planUuid) onStart;
  final VoidCallback onOpenProgram;

  @override
  Widget build(BuildContext context) {
    final eyebrow = 'TODAY · ${week.program.name.toUpperCase()}';
    final row = week.todayRow;
    final open = NsHeroAction('Open program', onOpenProgram);
    final next = week.nextTraining;
    final nextLabel = next == null
        ? 'No other training days'
        : 'Next: ${weekdayName(next.date)} · '
              '${week.plans[next.day.planUuid]?.name ?? 'Workout'}';
    final planUuid = row?.day.planUuid;
    final plan = planUuid == null ? null : week.plans[planUuid];
    switch (row?.status) {
      case ProgramDayStatus.today when plan != null:
        final count = plan.exercises.length;
        return NsHeroFrame(
          eyebrow: eyebrow,
          title: plan.name,
          subtitle:
              '$count ${count == 1 ? 'exercise' : 'exercises'} · '
              'about ${estimatedPlanMinutes(plan)} min',
          actions: [NsHeroAction('Start', () => onStart(plan.uuid)), open],
        );
      case ProgramDayStatus.done:
        return NsHeroFrame(
          eyebrow: eyebrow,
          title: 'Done for today',
          subtitle: nextLabel,
          actions: [open],
        );
      case ProgramDayStatus.unavailable:
        return NsHeroFrame(
          eyebrow: eyebrow,
          title: 'Workout unavailable',
          subtitle:
              'Today\'s workout was removed. Choose another in your '
              'program.',
          actions: [open],
        );
      default:
        return NsHeroFrame(
          eyebrow: eyebrow,
          title: 'Rest day',
          subtitle: nextLabel,
          actions: [open],
        );
    }
  }
}

/// "Missed WEEKDAY: WORKOUT" for the most recent missed day.
class TodayMissedLine extends StatelessWidget {
  const TodayMissedLine({required this.week, required this.onTap, super.key});

  final ProgramWeek week;
  final void Function(DateTime date, String planUuid, String workout) onTap;

  @override
  Widget build(BuildContext context) {
    final missed = week.latestMissed;
    final planUuid = missed?.day.planUuid;
    final plan = planUuid == null ? null : week.plans[planUuid];
    if (missed == null || plan == null) return const SizedBox.shrink();
    final title = 'Missed ${weekdayName(missed.date)}: ${plan.name}';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        label: '$title. Start it now',
        button: true,
        excludeSemantics: true,
        onTap: () => onTap(missed.date, plan.uuid, plan.name),
        child: NsListCard(
          icon: Icons.history,
          title: title,
          subtitle: 'Tap to start it now',
          onTap: () => onTap(missed.date, plan.uuid, plan.name),
        ),
      ),
    );
  }
}
