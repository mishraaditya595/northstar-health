import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/clock.dart';
import '../../core/date_labels.dart';
import '../../core/design/dialogs.dart';
import '../../core/design/beyondrep_theme.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import '../account/account_auth_provider.dart';
import '../health/widgets/today_health_row.dart';
import '../progress/domain/progress_overview.dart';
import '../progress/domain/workout_history_models.dart';
import '../progress/workout_history_state.dart';
import '../sync/workout_upload_coordinator.dart';
import '../sync/workout_conflict_resolution.dart';
import '../train/active_workout_state.dart';
import '../train/train_library_state.dart';
import '../workouts/data/objectbox_workout_outbox.dart';
import 'backup_status_notice.dart';
import 'today_overview.dart';

class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  int _count(WorkoutSyncFlag flag) => ref
      .watch(workoutSyncFlagsProvider)
      .values
      .where((value) => value == flag)
      .length;

  Future<void> _open(String route) async {
    await context.push<void>(route);
    ref.invalidate(trainLibraryProvider);
  }

  void _startPlan(String uuid) {
    try {
      ref.read(workoutActionsProvider).startPlan(uuid);
      ref.invalidate(activeWorkoutProvider);
      context.push('/train/workout');
    } catch (_) {
      showNsMessage(
        context,
        'Could not start this workout. Check the plan and any unfinished workout.',
      );
      ref.invalidate(activeWorkoutProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(localNowProvider);
    final today = DateTime.utc(now.year, now.month, now.day);
    final library = ref.watch(trainLibraryProvider);
    final history = ref.watch(completedWorkoutHistoryProvider);
    final unfinished = ref.watch(activeWorkoutProvider).value;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        PageHeader(
          title: 'Today',
          eyebrow: todayEyebrow(now),
          actions: [
            SquareButton(
              tooltip: 'Account and backup',
              onPressed: () => context.push('/today/account'),
              child: const Icon(Icons.manage_accounts_outlined, size: 20),
            ),
          ],
        ),
        BackupStatusNotice(
          controller: ref.watch(accountAuthControllerProvider),
          blockedCount: ref.watch(blockedWorkoutCountProvider),
          unsyncedCount: _count(WorkoutSyncFlag.notSynced),
          reviewCount: _count(WorkoutSyncFlag.needsReview),
          restoreBlocked: ref.watch(workoutRestoreBlockedCodeProvider) != null,
          onSyncNow: ref.watch(workoutUploadKickProvider),
          onReview: () => context.push('/today/sync/review'),
        ),
        const SizedBox(height: 24),
        if (unfinished != null)
          _HeroFrame(
            eyebrow: 'UNFINISHED WORKOUT',
            title: unfinished.session.name,
            subtitle: 'Saved on this device. Pick up where you left off.',
            actions: [
              _HeroButton('Resume', () => context.push('/train/workout')),
            ],
          )
        // A reload keeps showing the last value instead of a spinner.
        else if (library.hasValue && history.hasValue)
          _Hero(
            next: nextPlan(library.value!.plans, history.value!.sessions),
            onStart: _startPlan,
            onOpen: _open,
            onTrain: () => context.go('/train'),
          )
        else if (library.hasError || history.hasError)
          _HeroFrame(
            eyebrow: 'NEXT UP',
            title: 'Could not load your plans',
            subtitle: 'Your local plans and workouts were not changed.',
            actions: [
              _HeroButton('Retry', () {
                ref.invalidate(trainLibraryProvider);
                ref.invalidate(completedWorkoutHistoryProvider);
              }),
            ],
          )
        else
          const _HeroFrame(
            eyebrow: 'NEXT UP',
            title: null,
            subtitle: null,
            actions: [],
          ),
        const SizedBox(height: 27),
        const SectionHeading('Recent health'),
        const TodayHealthRow(),
        const SizedBox(height: 27),
        const SectionHeading('This week'),
        _WeekCard(
          today: today,
          perDay: history.hasValue
              ? sessionsPerDay(history.value!, today)
              : null,
          failed: !history.hasValue && history.hasError,
        ),
      ],
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.today,
    required this.perDay,
    required this.failed,
  });

  final DateTime today;

  /// Finished sessions per day, Sunday first; null while loading.
  final List<int>? perDay;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<BeyondRepColors>()!;
    final counts = perDay;
    final total = counts?.fold(0, (a, b) => a + b) ?? 0;
    final days = weekDays(today);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failed
                  ? 'Could not load finished workouts'
                  : counts == null
                  ? 'Loading finished workouts…'
                  : total == 0
                  ? 'No workouts finished yet this week'
                  : '$total ${total == 1 ? 'workout' : 'workouts'} finished this week',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sunday to Saturday · finished workouts on this device',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
            ),
            if (counts != null) ...[
              const SizedBox(height: 13),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < days.length; i++)
                    _Day(
                      name: weekdayName(days[i]),
                      isToday: days[i] == today,
                      trained: counts[i] > 0,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroButton {
  const _HeroButton(this.label, this.onPressed);
  final String label;
  final VoidCallback onPressed;
}

/// Suggests the next saved plan; there is no schedule, see [nextPlan].
class _Hero extends StatelessWidget {
  const _Hero({
    required this.next,
    required this.onStart,
    required this.onOpen,
    required this.onTrain,
  });

  final NextPlan? next;
  final void Function(String planUuid) onStart;
  final void Function(String route) onOpen;
  final VoidCallback onTrain;

  @override
  Widget build(BuildContext context) {
    final suggestion = next;
    if (suggestion == null) {
      return _HeroFrame(
        eyebrow: 'GET STARTED',
        title: 'No plans yet',
        subtitle:
            'Create a plan, or go to Train for a quick workout and add '
            'exercises as you go.',
        actions: [
          _HeroButton('Create a plan', () => onOpen('/train/plans/new')),
          _HeroButton('Go to Train', onTrain),
        ],
      );
    }
    final plan = suggestion.plan;
    final count = plan.exercises.length;
    final last = suggestion.lastDone;
    return _HeroFrame(
      eyebrow: 'NEXT UP',
      title: plan.name,
      subtitle:
          '$count ${count == 1 ? 'exercise' : 'exercises'} · '
          '${last == null ? 'Not done yet' : 'Last done ${formatWorkoutDay(originalLocalDay(last))}'}',
      actions: [
        _HeroButton('Start workout', () => onStart(plan.uuid)),
        _HeroButton('Edit', () => onOpen('/train/plans/${plan.uuid}/edit')),
      ],
    );
  }
}

class _HeroFrame extends StatelessWidget {
  const _HeroFrame({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String eyebrow;

  /// Null while loading: a spinner replaces title, subtitle and actions.
  final String? title;
  final String? subtitle;

  /// The first action is the filled primary button.
  final List<_HeroButton> actions;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const subtle = Color(0xFFBCCFC1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? BeyondRepPalette.heroDark : BeyondRepPalette.heroLight,
          border: Border.all(color: BeyondRepPalette.heroBorder),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -32,
              bottom: -55,
              child: IgnorePointer(
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: BeyondRepPalette.lime.withValues(alpha: .25),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: BeyondRepPalette.lime.withValues(alpha: .04),
                        spreadRadius: 22,
                      ),
                      BoxShadow(
                        color: BeyondRepPalette.lime.withValues(alpha: .03),
                        spreadRadius: 44,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: const TextStyle(
                      color: Color(0xFFB7DBC1),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 9),
                  if (title == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Semantics(
                          label: 'Loading your plans',
                          child: const CircularProgressIndicator(),
                        ),
                      ),
                    )
                  else ...[
                    Semantics(
                      header: true,
                      child: Text(
                        title!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.8,
                        ),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: subtle,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 17),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          FilledButton(
                            onPressed: actions.first.onPressed,
                            style: FilledButton.styleFrom(
                              backgroundColor: BeyondRepPalette.lime,
                              foregroundColor: const Color(0xFF111A10),
                              minimumSize: const Size(0, 46),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 17,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            child: Text(actions.first.label),
                          ),
                          for (final action in actions.skip(1))
                            TextButton(
                              onPressed: action.onPressed,
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFCFE4D3),
                                minimumSize: const Size(44, 44),
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              child: Text(action.label),
                            ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.name,
    required this.isToday,
    required this.trained,
  });

  final String name;
  final bool isToday;
  final bool trained;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Semantics(
      label: [name, if (isToday) 'today', if (trained) 'trained'].join(', '),
      excludeSemantics: true,
      child: Column(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: trained ? primary : null,
              border: Border.all(
                color: trained || isToday ? primary : theme.colorScheme.outline,
                width: isToday ? 2 : 1,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            name.substring(0, 3),
            style: theme.textTheme.labelSmall?.copyWith(
              color: isToday
                  ? theme.colorScheme.onSurface
                  : theme.extension<BeyondRepColors>()!.muted,
              fontWeight: isToday ? FontWeight.w800 : null,
            ),
          ),
        ],
      ),
    );
  }
}
