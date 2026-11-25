import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/page_header.dart';
import '../../../core/design/stats.dart';
import '../application/health_overview.dart';
import '../application/health_summary_controller.dart';
import '../domain/readiness.dart';
import '../health_format.dart';
import 'health_actions_mixin.dart';
import 'health_connect_card.dart';
import 'readiness_card.dart';

typedef _Tile = ({
  String label,
  String? value,
  String? unit,
  String caption,
  MetricGap? gap,
  String? route,
});

_Tile _gapTile(String label, MetricGap gap, String noData) => (
  label: label,
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
);

const _noSleep = 'No sleep recorded last night';
const _noSteps = 'No steps yet today';
const _noRestingHr = 'None in the last 30 days';

_Tile _sleep(HealthOverview o) => switch (o.sleep) {
  SectionGap(:final gap) => _gapTile('Sleep', gap, _noSleep),
  SectionData(:final value) =>
    value.lastNight.date ==
            DateTime(o.readAt.year, o.readAt.month, o.readAt.day)
        ? (
            label: 'Sleep',
            value: formatDuration(value.lastNight.asleep),
            unit: null,
            caption:
                '${value.lastNight.source} · ended '
                '${formatClockTime(value.lastNight.end)}',
            gap: null,
            route: null,
          )
        : _gapTile('Sleep', MetricGap.noData, _noSleep),
};

_Tile _steps(HealthOverview o) => switch (o.activity) {
  SectionGap(:final gap) => _gapTile('Steps', gap, _noSteps),
  SectionData(value: ActivityOverview(stepsToday: final steps?)) => (
    label: 'Steps',
    value: formatCount(steps),
    unit: null,
    caption:
        '${healthPlatformName(o.platform)} · as of '
        '${formatClockTime(o.readAt)}',
    gap: null,
    route: null,
  ),
  SectionData(value: ActivityOverview(stepsGap: final gap?)) => _gapTile(
    'Steps',
    gap,
    _noSteps,
  ),
  SectionData() => _gapTile('Steps', MetricGap.noData, _noSteps),
};

_Tile _restingHr(HealthOverview o) => switch (o.heart) {
  SectionGap(:final gap) => _gapTile('Resting HR', gap, _noRestingHr),
  SectionData(value: HeartOverview(restingHr: final hr?)) => (
    label: 'Resting HR',
    value: '${hr.value.round()}',
    unit: 'bpm',
    caption: hr.day == DateTime(o.readAt.year, o.readAt.month, o.readAt.day)
        ? 'Today'
        : formatHealthDate(hr.day),
    gap: null,
    route: null,
  ),
  SectionData(value: HeartOverview(restingHrGap: final gap?)) => _gapTile(
    'Resting HR',
    gap,
    _noRestingHr,
  ),
  SectionData() => _gapTile('Resting HR', MetricGap.noData, _noRestingHr),
};

/// Only a ready readiness earns a slot; any other state keeps stage 1's row.
_Tile? _readiness(HealthOverview o) => switch (o.readiness) {
  SectionData(
    value: ReadinessOverview(result: ReadinessReady(:final readiness)),
  ) =>
    (
      label: 'Readiness',
      value: '${readiness.value}',
      unit: null,
      caption: readinessBandWords(readiness.band),
      gap: null,
      route: '/health/readiness',
    ),
  _ => null,
};

/// Today tab "Recent health": a Connect card, or sleep, steps and resting HR
/// from the Health overview (no reads of its own).
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
    final readiness = _readiness(overview);
    final tiles = [
      ?readiness,
      _sleep(overview),
      _steps(overview),
      if (readiness == null) _restingHr(overview),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, t) in tiles.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: t.label,
                value: t.value ?? '—',
                unit: t.value == null ? null : t.unit,
                caption: t.caption,
                onTap: t.route != null
                    ? () => context.push(t.route!)
                    : _actionFor(t.gap, busy),
              ),
            ),
          ],
        ],
      ),
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
