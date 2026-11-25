import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/clock.dart';
import '../../core/design/beyondrep_theme.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import 'application/health_overview.dart';
import 'application/health_summary_controller.dart';
import 'application/training_insights.dart';
import 'data/health_reader.dart';
import 'health_format.dart';
import 'widgets/activity_card.dart';
import 'widgets/body_card.dart';
import 'widgets/health_actions_mixin.dart';
import 'widgets/health_card_frame.dart';
import 'widgets/health_connect_card.dart';
import 'widgets/heart_card.dart';
import 'widgets/readiness_card.dart';
import 'widgets/sleep_card.dart';
import 'widgets/training_insight_line.dart';

const _iosHint =
    "Missing something? Check BeyondRep's access in the Health app.";
const _disconnectHint =
    'To stop BeyondRep reading health data on this phone, turn it off in '
    'Health settings.';

class HealthPage extends ConsumerStatefulWidget {
  const HealthPage({super.key});

  @override
  ConsumerState<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends ConsumerState<HealthPage>
    with HealthActionsMixin {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.extension<BeyondRepColors>()!.muted;
    final async = ref.watch(healthSummaryProvider);
    final state = async.value;
    final loading = async.isLoading;
    return RefreshIndicator(
      onRefresh: () async {
        try {
          await Future.wait([
            ref.read(healthSummaryProvider.notifier).refresh(),
            ref.read(healthOverviewProvider.notifier).refresh(),
          ]);
        } catch (_) {
          // The failure shows as the overview's error state (Try again).
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          const PageHeader(title: 'Health'),
          const SizedBox(height: 24),
          if (state == null && async.hasError)
            InsightCard(
              icon: Icons.favorite_border,
              text: const TextSpan(text: "Couldn't load health."),
              actionLabel: 'Try again',
              onAction: guarded(loading, (c) => c.refresh()),
            )
          else if (state == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (state is HealthNotConnected)
            HealthConnectCard(
              availability: state.availability,
              platform: state.platform,
              onAction: guardedConnect(loading),
            )
          else
            ..._connected(context, state as HealthConnected, loading, muted),
        ],
      ),
    );
  }

  @override
  void onShownOrResumed() {
    ref.read(healthOverviewProvider.notifier).refreshIfStale();
  }

  List<Widget> _connected(
    BuildContext context,
    HealthConnected state,
    bool loading,
    Color muted,
  ) {
    final theme = Theme.of(context);
    final async = ref.watch(healthOverviewProvider);
    final overview = async.value;
    final busy = loading || async.isLoading;
    final sections = overview == null
        ? const <Section<Object>>[]
        : <Section<Object>>[
            overview.sleep,
            overview.heart,
            overview.activity,
            overview.body,
          ];
    bool hasGap(MetricGap gap) =>
        sections.any((s) => s is SectionGap<Object> && s.gap == gap);
    final allowMore = guardedOverview(busy, (c) => c.requestMoreAccess());

    /// Data opens the detail; Not allowed -> Manage, Couldn't read -> Try
    /// again; nothing for other gaps.
    VoidCallback? tapFor(Section<Object> section, String detail) =>
        switch (section) {
          SectionData() => () => context.push(detail),
          SectionGap(gap: MetricGap.notAllowed) => guarded(
            busy,
            (c) => c.manage(),
          ),
          SectionGap(gap: MetricGap.failed) => guardedOverview(
            busy,
            (c) => c.refresh(),
          ),
          SectionGap() => null,
        };

    final insights = ref.watch(trainingInsightsProvider);
    final insightLine = insights?.sleep != null
        ? TrainingInsightLine.sleep(insights!.sleep!)
        : insights?.restingHr != null
        ? TrainingInsightLine.restingHr(insights!.restingHr!)
        : null;

    final List<Widget> cards;
    if (overview != null) {
      final platform = overview.platform;
      // The overview's own day, as on the detail pages and the Today row.
      final readAt = overview.readAt;
      final today = DateTime(readAt.year, readAt.month, readAt.day);
      cards = [
        SleepCard(
          section: overview.sleep,
          platform: platform,
          today: today,
          onTap: tapFor(overview.sleep, '/health/sleep'),
          onAllowMore: allowMore,
        ),
        HeartCard(
          section: overview.heart,
          platform: platform,
          today: today,
          onTap: tapFor(overview.heart, '/health/heart'),
          onAllowMore: allowMore,
        ),
        ActivityCard(
          section: overview.activity,
          platform: platform,
          today: today,
          onTap: tapFor(overview.activity, '/health/activity'),
          onAllowMore: allowMore,
        ),
        BodyCard(
          section: overview.body,
          platform: platform,
          today: today,
          onTap: tapFor(overview.body, '/health/body'),
          onAllowMore: allowMore,
        ),
      ];
    } else {
      cards = const [
        HealthCardPlaceholder(
          title: 'Sleep',
          icon: Icons.bedtime_outlined,
          sleepTint: true,
        ),
        HealthCardPlaceholder(title: 'Heart', icon: Icons.favorite_border),
        HealthCardPlaceholder(title: 'Activity', icon: Icons.directions_walk),
        HealthCardPlaceholder(
          title: 'Body',
          icon: Icons.monitor_weight_outlined,
        ),
      ];
    }

    return [
      if (overview != null) ...[
        Text(
          formatOverviewDateLine(overview.readAt, overview.platform),
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 14),
      ],
      if (overview == null && async.hasError) ...[
        InsightCard(
          icon: Icons.favorite_border,
          text: const TextSpan(text: "Couldn't read health data."),
          actionLabel: 'Try again',
          onAction: guardedOverview(busy, (c) => c.refresh()),
        ),
        const SizedBox(height: 14),
      ],
      if (overview != null &&
          overview.needsMoreAccess &&
          !hasGap(MetricGap.needsAccess)) ...[
        InsightCard(
          icon: Icons.lock_open,
          text: const TextSpan(
            text: 'Some cards can show more once BeyondRep may read it.',
          ),
          actionLabel: 'Allow more data',
          onAction: allowMore,
        ),
        const SizedBox(height: 14),
      ],
      if (overview != null || !async.hasError) ...[
        ReadinessCard(
          overview: overview,
          now: ref.watch(localNowProvider),
          refreshing: async.isLoading,
          onTap: overview == null
              ? null
              : hasStaleReadiness(overview, ref.watch(localNowProvider))
              ? guardedOverview(busy, (c) => c.refresh())
              : tapFor(overview.readiness, '/health/readiness'),
          onAllowMore: allowMore,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 560;
            // Activity and Body pair up on phones too, unless large text
            // leaves each half too narrow.
            final pairSmall =
                box.maxWidth >= MediaQuery.textScalerOf(context).scale(300);
            Widget pair(Widget a, Widget b, bool side) => side
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: a),
                      const SizedBox(width: 10),
                      Expanded(child: b),
                    ],
                  )
                : Column(children: [a, const SizedBox(height: 10), b]);
            return Column(
              children: [
                pair(cards[0], cards[1], wide),
                const SizedBox(height: 10),
                pair(cards[2], cards[3], wide || pairSmall),
              ],
            );
          },
        ),
      ],
      if (insightLine != null) ...[
        const SizedBox(height: 24),
        const SectionHeading('From your training'),
        insightLine,
      ],
      if (state.platform == HealthPlatformKind.appleHealth &&
          hasGap(MetricGap.noData)) ...[
        const SizedBox(height: 12),
        Text(
          _iosHint,
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
      const SizedBox(height: 27),
      Row(
        children: [
          Expanded(
            child: Text(
              _disconnectHint,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          TextButton(
            onPressed: guarded(loading, (c) => c.disconnect()),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    ];
  }
}
