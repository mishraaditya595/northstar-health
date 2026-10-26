import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/dialogs.dart';
import '../../core/design/northstar_theme.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import '../account/account_auth_provider.dart';
import '../sync/workout_upload_coordinator.dart';
import '../workouts/data/objectbox_workout_outbox.dart';
import 'backup_status_notice.dart';

class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  String? energy;

  void _later() => showNsMessage(context, 'Available in a later phase.');

  Future<void> _signOut() async {
    final yes = await showNsConfirm(
      context,
      title: 'Sign out?',
      message:
          'Your workouts stay on this device, including any unfinished '
          'session, and come back when you sign in to this account again.',
      confirmLabel: 'Sign out',
    );
    if (!yes) return;
    final auth = ref.read(accountAuthControllerProvider);
    if (auth == null) return;
    await auth.signOut();
    // A failed sign-out keeps the account open, so say so.
    if (auth.error != null && mounted) showNsMessage(context, auth.error!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final colors = theme.extension<NorthstarColors>()!;
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
          eyebrow: 'FICTIONAL DEMO DATA · 23 OCT 2026',
          actions: [
            SquareButton(
              tooltip: 'Sign out of NorthStar',
              onPressed: _signOut,
              child: const Icon(Icons.logout_rounded, size: 20),
            ),
          ],
        ),
        BackupStatusNotice(
          controller: ref.watch(accountAuthControllerProvider),
          blockedCount: ref.watch(blockedWorkoutCountProvider),
          unsyncedCount: ref
              .watch(workoutSyncFlagsProvider)
              .values
              .where((flag) => flag == WorkoutSyncFlag.notSynced)
              .length,
          onSyncNow: ref.watch(workoutUploadKickProvider),
        ),
        const SizedBox(height: 24),
        _Hero(
          onStart: () => context.go('/train'),
          onEdit: _later,
          onMove: _later,
        ),
        const SizedBox(height: 27),
        const SectionHeading('Energy check-in', action: 'Edit later'),
        Row(
          children: [
            for (final item in const ['Low', 'Okay', 'Good', 'Skip']) ...[
              if (item != 'Low') const SizedBox(width: 8),
              Expanded(
                child: _EnergyChip(
                  label: item,
                  selected: energy == item,
                  onTap: () => setState(() => energy = item),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 27),
        const SectionHeading('Recent health', action: 'See all'),
        const Row(
          children: [
            Expanded(
              child: _Metric(
                'Sleep',
                '6h 18m',
                'Apple Health · Today',
                Icons.bedtime_outlined,
                sleep: true,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _Metric(
                'Steps',
                '6,420',
                'Updated 18:20',
                Icons.directions_walk,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _Metric(
                'Resting HR',
                '58 bpm',
                '23 Oct · Apple',
                Icons.favorite_border,
              ),
            ),
          ],
        ),
        const SizedBox(height: 27),
        const SectionHeading('One useful context'),
        InsightCard(
          icon: Icons.nights_stay_outlined,
          text: const TextSpan(
            children: [
              TextSpan(text: 'Your last recorded sleep was '),
              TextSpan(
                text: '52 min shorter',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(text: ' than your recent average.'),
            ],
          ),
          actionLabel: 'View',
          onAction: () => context.go('/health'),
        ),
        const SizedBox(height: 27),
        const SectionHeading('This week', action: 'Weekly review'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        '2 of 3 planned sessions complete',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      'Friday session',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: 2 / 3,
                    minHeight: 8,
                    backgroundColor: dark
                        ? NorthstarPalette.darkSoft
                        : NorthstarPalette.lightSoft,
                  ),
                ),
                const SizedBox(height: 11),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    _Day('Mon', _DayState.done),
                    _Day('Wed', _DayState.done),
                    _Day('Fri', _DayState.today),
                    _Day('Sun', _DayState.upcoming),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.onStart,
    required this.onEdit,
    required this.onMove,
  });

  final VoidCallback onStart;
  final VoidCallback onEdit;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const subtle = Color(0xFFBCCFC1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? NorthstarPalette.heroDark : NorthstarPalette.heroLight,
          border: Border.all(color: NorthstarPalette.heroBorder),
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
                      color: NorthstarPalette.lime.withValues(alpha: .25),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: NorthstarPalette.lime.withValues(alpha: .04),
                        spreadRadius: 22,
                      ),
                      BoxShadow(
                        color: NorthstarPalette.lime.withValues(alpha: .03),
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
                  const Text(
                    'PLANNED FOR TODAY',
                    style: TextStyle(
                      color: Color(0xFFB7DBC1),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 9),
                  const Text(
                    'Full Body A',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '5 exercises · Around 45 min · Gym',
                    style: TextStyle(color: subtle, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 17),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      FilledButton(
                        onPressed: onStart,
                        style: FilledButton.styleFrom(
                          backgroundColor: NorthstarPalette.lime,
                          foregroundColor: const Color(0xFF111A10),
                          minimumSize: const Size(0, 46),
                          padding: const EdgeInsets.symmetric(horizontal: 17),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: const Text('Start workout'),
                      ),
                      for (final entry in {
                        'Edit': onEdit,
                        'Move': onMove,
                      }.entries)
                        TextButton(
                          onPressed: entry.value,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFCFE4D3),
                            minimumSize: const Size(44, 44),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: Text(entry.key),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnergyChip extends StatelessWidget {
  const _EnergyChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final selectedBg = theme.colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? selectedBg : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: selected ? selectedBg : theme.colorScheme.outline,
          ),
          borderRadius: BorderRadius.circular(13),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? (dark ? NorthstarPalette.heroDark : Colors.white)
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
    this.name,
    this.value,
    this.source,
    this.icon, {
    this.sleep = false,
  });

  final String name;
  final String value;
  final String source;
  final IconData icon;
  final bool sleep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.extension<NorthstarColors>()!.muted;
    final iconBg = sleep
        ? (dark
              ? NorthstarPalette.sleepSoftDark
              : NorthstarPalette.sleepSoftLight)
        : (dark
              ? NorthstarPalette.forestSoftDark
              : NorthstarPalette.forestSoftLight);
    final iconColor = sleep
        ? (dark ? NorthstarPalette.sleepDark : NorthstarPalette.sleepLight)
        : theme.colorScheme.primary;
    return Semantics(
      label: '$name: $value. $source',
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 15, color: iconColor),
              ),
              const SizedBox(height: 13),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DayState { done, today, upcoming }

class _Day extends StatelessWidget {
  const _Day(this.label, this.state);

  final String label;
  final _DayState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: switch (state) {
              _DayState.done => primary,
              _DayState.today => null,
              _DayState.upcoming => theme.colorScheme.outline,
            },
            border: state == _DayState.today
                ? Border.all(color: primary, width: 2)
                : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.extension<NorthstarColors>()!.muted,
          ),
        ),
      ],
    );
  }
}
