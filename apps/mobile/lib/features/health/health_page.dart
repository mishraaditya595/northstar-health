import 'package:flutter/material.dart';

import '../../core/design/northstar_theme.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';

class HealthPage extends StatelessWidget {
  const HealthPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.extension<NorthstarColors>()!.muted;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        const PageHeader(
          title: 'Health',
          eyebrow: 'FICTIONAL DEMO DATA · 23 OCT 2026',
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const NsTag('Not connected'),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Health platforms are not linked yet',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 17),
        const InsightCard(
          icon: Icons.sync,
          text: TextSpan(
            text:
                'Permissioned Apple Health and Health Connect support will '
                'arrive in a later milestone. The values below are fictional.',
          ),
        ),
        const SizedBox(height: 27),
        const SectionHeading('Today'),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 560 ? 2 : 1;
            final width = (box.maxWidth - 10 * (columns - 1)) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final stat in const [
                  _Stat(
                    'Sleep',
                    '6h 18m',
                    'Night ending 23 Oct · Demo',
                    Icons.bedtime_outlined,
                    sleep: true,
                  ),
                  _Stat(
                    'Steps',
                    '6,420',
                    '23 Oct · Demo',
                    Icons.directions_walk,
                  ),
                  _Stat(
                    'Resting heart rate',
                    '58 bpm',
                    '23 Oct · Demo',
                    Icons.favorite_border,
                  ),
                  _Stat(
                    'Weight',
                    '74.2 kg',
                    'Entered 22 Oct · Demo',
                    Icons.monitor_weight_outlined,
                  ),
                ])
                  SizedBox(width: width, child: stat),
              ],
            );
          },
        ),
        const SizedBox(height: 27),
        const SectionHeading('Imported activities'),
        const NsListCard(
          icon: Icons.directions_walk,
          title: 'Outdoor walk',
          subtitle: '22 Oct · 28 min · Demo summary',
          trailing: NsTag('Demo'),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
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
          padding: const EdgeInsets.all(16),
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
                style: theme.textTheme.labelMedium?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                source,
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
