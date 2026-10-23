import 'package:flutter/material.dart';
import 'northstar_theme.dart';

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
        ),
      );
}

class DemoLabel extends StatelessWidget {
  const DemoLabel({super.key});

  @override
  Widget build(BuildContext context) => Text(
        'FICTIONAL DEMO DATA · 23 OCT 2026',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context)
                  .extension<NorthstarColors>()!
                  .muted,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
      );
}
