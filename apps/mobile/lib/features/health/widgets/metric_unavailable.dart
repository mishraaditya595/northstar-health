import 'package:flutter/material.dart';

import '../application/health_overview.dart';
import '../data/health_reader.dart';
import '../health_format.dart';
import 'health_card_frame.dart';

/// Why [metricName] ('Sleep', 'Heart', 'Activity', 'Body') has nothing to
/// show, and what would provide it.
String metricUnavailableText(
  MetricGap gap,
  String metricName,
  HealthPlatformKind platform,
) => switch (gap) {
  MetricGap.noData => switch (metricName) {
    'Sleep' =>
      'No sleep recorded. A watch, ring or sleep app that writes to '
          '${healthPlatformName(platform)} fills this in.',
    'Heart' =>
      platform == HealthPlatformKind.appleHealth
          ? "iPhone alone doesn't measure heart rate. Shown when a wearable "
                'provides it.'
          : 'Shown when a watch or ring provides it.',
    'Activity' => 'No steps or active calories in the last 30 days.',
    'Body' => 'No weight or body fat in the last 30 days.',
    _ => 'Nothing recorded in the last 30 days.',
  },
  MetricGap.needsAccess => "BeyondRep isn't allowed to read this yet.",
  MetricGap.notAllowed => 'Not allowed · Manage',
  MetricGap.failed => "Couldn't read · Try again",
  MetricGap.unsupported => 'Not available on this device',
};

/// `—` plus the reason; "Allow more data" for [MetricGap.needsAccess] when
/// [onAction] is set. Not allowed / Couldn't read are handled by tapping the
/// card, as on the Phase 3 cards.
class MetricUnavailable extends StatelessWidget {
  const MetricUnavailable({
    required this.gap,
    required this.metricName,
    required this.platform,
    this.onAction,
    super.key,
  });

  final MetricGap gap;
  final String metricName;
  final HealthPlatformKind platform;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = metricUnavailableText(gap, metricName, platform);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'No $metricName data. $text',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const HealthValue(null),
              const SizedBox(height: 4),
              HealthCaption(text),
            ],
          ),
        ),
        if (gap == MetricGap.needsAccess && onAction != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton(
              onPressed: onAction,
              child: const Text('Allow more data'),
            ),
          ),
      ],
    );
  }
}
