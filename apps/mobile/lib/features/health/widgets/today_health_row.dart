import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/page_header.dart';
import '../application/health_summary_controller.dart';
import '../data/health_reader.dart';
import 'health_actions_mixin.dart';
import 'health_connect_card.dart';
import 'health_metric_card.dart';

const _todayMetrics = [
  HealthMetric.sleep,
  HealthMetric.steps,
  HealthMetric.restingHeartRate,
];

/// Today tab "Recent health": a Connect card, or sleep, steps, resting HR.
class TodayHealthRow extends ConsumerStatefulWidget {
  const TodayHealthRow({super.key});

  @override
  ConsumerState<TodayHealthRow> createState() => _TodayHealthRowState();
}

class _TodayHealthRowState extends ConsumerState<TodayHealthRow>
    with HealthActionsMixin {
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return switch (state) {
      HealthNotConnected() => HealthConnectCard(
        availability: state.availability,
        platform: state.platform,
        onAction: guarded(loading, (c) => c.connect()),
      ),
      HealthConnected() => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final metric in _todayMetrics) ...[
              if (metric != _todayMetrics.first) const SizedBox(width: 10),
              Expanded(
                child: HealthMetricCard(
                  metric: metric,
                  reading: state.readings[metric] ?? const HealthNoData(),
                  platform: state.platform,
                  now: state.readAt,
                  compact: true,
                  onAction: actionForReading(state.readings[metric], loading),
                ),
              ),
            ],
          ],
        ),
      ),
    };
  }
}
