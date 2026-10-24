import 'package:flutter/material.dart';

import 'northstar_theme.dart';

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {this.action, super.key});

  final String title;
  final String? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (action != null)
            Text(
              action!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.mutedColor,
              ),
            ),
        ],
      ),
    );
  }
}

class DemoLabel extends StatelessWidget {
  const DemoLabel({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'FICTIONAL DEMO DATA · 23 OCT 2026',
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).mutedColor,
      letterSpacing: 1.1,
      fontWeight: FontWeight.w700,
    ),
  );
}
