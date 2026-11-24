import 'package:flutter/material.dart';

import '../../../core/design/page_header.dart';
import '../data/health_reader.dart';
import '../health_format.dart';

/// The single card shown while health is not connected. [onAction] null keeps
/// the action visible but disabled (a request is in flight).
class HealthConnectCard extends StatelessWidget {
  const HealthConnectCard({
    required this.availability,
    required this.platform,
    required this.onAction,
    super.key,
  });

  final HealthAvailability availability;
  final HealthPlatformKind platform;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final name = healthPlatformName(platform);
    final bold = const TextStyle(fontWeight: FontWeight.w800);
    return switch (availability) {
      HealthAvailability.available => InsightCard(
        icon: Icons.favorite_border,
        text: TextSpan(
          children: [
            TextSpan(text: 'Connect $name\n', style: bold),
            const TextSpan(
              text:
                  "See today's sleep, steps, resting heart rate and weight. "
                  'Read-only; stays on this phone.',
            ),
          ],
        ),
        actionLabel: 'Connect',
        onAction: onAction,
      ),
      HealthAvailability.needsInstall => InsightCard(
        icon: Icons.favorite_border,
        text: TextSpan(
          children: [
            TextSpan(text: '$name is needed\n', style: bold),
            const TextSpan(
              text: 'Install it to see your sleep, steps and more here.',
            ),
          ],
        ),
        actionLabel: 'Get $name',
        onAction: onAction,
      ),
      HealthAvailability.unsupported => InsightCard(
        icon: Icons.favorite_border,
        text: TextSpan(text: "$name isn't available on this phone."),
      ),
    };
  }
}
