import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/beyondrep_theme.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import 'application/health_summary_controller.dart';
import 'data/health_reader.dart';
import 'widgets/health_actions_mixin.dart';
import 'widgets/health_connect_card.dart';
import 'widgets/health_metric_card.dart';

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
      onRefresh: () => ref.read(healthSummaryProvider.notifier).refresh(),
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
              onAction: guarded(loading, (c) => c.connect()),
            )
          else
            ..._connected(context, state as HealthConnected, loading, muted),
        ],
      ),
    );
  }

  List<Widget> _connected(
    BuildContext context,
    HealthConnected state,
    bool loading,
    Color muted,
  ) {
    final theme = Theme.of(context);
    final anyNoData = state.readings.values.any((r) => r is HealthNoData);
    return [
      const SectionHeading('Today'),
      LayoutBuilder(
        builder: (context, box) {
          final columns = box.maxWidth >= 560 ? 2 : 1;
          final width = (box.maxWidth - 10 * (columns - 1)) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final metric in HealthMetric.values)
                SizedBox(
                  width: width,
                  child: HealthMetricCard(
                    metric: metric,
                    reading: state.readings[metric] ?? const HealthNoData(),
                    platform: state.platform,
                    now: state.readAt,
                    onAction: actionForReading(state.readings[metric], loading),
                  ),
                ),
            ],
          );
        },
      ),
      if (anyNoData && state.platform == HealthPlatformKind.appleHealth) ...[
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
