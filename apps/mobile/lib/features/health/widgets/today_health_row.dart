import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clock.dart';
import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/page_header.dart';
import '../../../core/design/stats.dart';
import '../../progress/workout_history_state.dart';
import '../application/health_overview.dart';
import '../application/health_summary_controller.dart';
import '../data/health_reader.dart';
import '../domain/metric_explanations.dart';
import '../domain/readiness.dart';
import '../health_format.dart';
import 'health_actions_mixin.dart';
import 'health_connect_card.dart';
import 'metric_info_sheet.dart';
import 'readiness_card.dart';
import 'readiness_hero.dart';
import 'today_health_tiles.dart';

/// Today tab "Recent health": a Connect card, or today's readiness and a grid
/// of sleep, steps, resting HR and finished workouts from the Health overview
/// and local history (no health reads of its own).
class TodayHealthRow extends ConsumerStatefulWidget {
  const TodayHealthRow({super.key});

  @override
  ConsumerState<TodayHealthRow> createState() => _TodayHealthRowState();
}

class _TodayHealthRowState extends ConsumerState<TodayHealthRow>
    with HealthActionsMixin {
  @override
  void onShownOrResumed() {
    if (ref.read(healthSummaryProvider).value is HealthConnected) {
      ref.read(healthOverviewProvider.notifier).refreshIfStale();
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(healthSummaryProvider);
    final state = async.value;
    final loading = async.isLoading;
    if (state == null) {
      if (async.hasError) {
        return InsightCard(
          icon: Icons.favorite_border,
          text: const TextSpan(text: "Couldn't load health."),
          actionLabel: 'Try again',
          onAction: guarded(loading, (c) => c.refresh()),
        );
      }
      return const _Loading();
    }
    return switch (state) {
      HealthNotConnected() => HealthConnectCard(
        availability: state.availability,
        platform: state.platform,
        onAction: guardedConnect(loading),
      ),
      HealthConnected() => _connected(loading),
    };
  }

  Widget _connected(bool summaryLoading) {
    final async = ref.watch(healthOverviewProvider);
    final overview = async.value;
    final busy = summaryLoading || async.isLoading;
    if (overview == null) {
      if (async.hasError) {
        return InsightCard(
          icon: Icons.favorite_border,
          text: const TextSpan(text: "Couldn't read health data."),
          actionLabel: 'Try again',
          onAction: guardedOverview(busy, (c) => c.refresh()),
        );
      }
      return const _Loading();
    }
    final now = ref.watch(localNowProvider);
    final today = todaysReadiness(overview, now);
    final sessions =
        ref.watch(completedWorkoutHistoryProvider).value?.sessions ?? const [];
    final tiles = [
      sleepTile(overview),
      stepsTile(overview),
      restingHrTile(overview),
      workoutsTile(sessions, now),
    ];
    final theme = Theme.of(context);
    final narrow =
        MediaQuery.textScalerOf(context).scale(1) >= 1.6 ||
        MediaQuery.sizeOf(context).width < 360;
    Widget tile(TodayTile t) => _tile(t, overview.platform, busy);
    final hero = switch (today?.result) {
      ReadinessReady(:final readiness) => ReadinessHero(
        readiness: readiness,
        reasons: readinessReasons(overview, today!, readiness),
        platform: overview.platform,
        onOpen: () => context.push('/health/readiness'),
      ),
      ReadinessNotReady(:final daysUntilBaseline?) => InsightCard(
        icon: Icons.bolt_outlined,
        text: TextSpan(text: readinessBuildingText(daysUntilBaseline)),
      ),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hero != null) ...[hero, const SizedBox(height: 10)],
        if (narrow)
          for (final (i, t) in tiles.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            tile(t),
          ]
        else
          for (var i = 0; i < tiles.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tile(tiles[i])),
                  const SizedBox(width: 10),
                  Expanded(child: tile(tiles[i + 1])),
                ],
              ),
            ),
          ],
        const SizedBox(height: 10),
        Text(
          'From ${healthPlatformName(overview.platform)}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.mutedColor),
        ),
      ],
    );
  }

  Widget _tile(TodayTile t, HealthPlatformKind platform, bool busy) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final key = t.infoKey;
    return StatTile(
      label: t.label,
      value: t.value ?? '—',
      unit: t.value == null ? null : t.unit,
      caption: t.caption,
      icon: t.icon,
      iconColor: t.sleepTint
          ? (dark ? BeyondRepPalette.sleepDark : BeyondRepPalette.sleepLight)
          : theme.colorScheme.primary,
      onTap: t.route != null
          ? () => context.push(t.route!)
          : _actionFor(t.gap, busy),
      onInfo: key == null
          ? null
          : () => showMetricInfo(
              context,
              key,
              platform: platform,
              usual: t.usual,
              unit: t.unit,
            ),
      infoLabel: key == null
          ? null
          : 'About ${explanationFor(key, platform).title}',
    );
  }

  /// Not allowed -> Manage, Couldn't read -> Try again, never requested ->
  /// Allow more data; none otherwise.
  VoidCallback? _actionFor(MetricGap? gap, bool busy) => switch (gap) {
    MetricGap.notAllowed => guarded(busy, (c) => c.manage()),
    MetricGap.failed => guardedOverview(busy, (c) => c.refresh()),
    MetricGap.needsAccess => guardedOverview(
      busy,
      (c) => c.requestMoreAccess(),
    ),
    _ => null,
  };
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: CircularProgressIndicator(),
    ),
  );
}
