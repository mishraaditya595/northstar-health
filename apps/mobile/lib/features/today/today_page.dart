import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme_controller.dart';
import '../../core/design/northstar_theme.dart';
import '../../core/design/section.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        24,
        20,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DemoLabel(),
                  const SizedBox(height: 8),
                  Text(
                    'TODAY',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.8,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: dark ? 'Use light mode' : 'Use dark mode',
              onPressed: () => ref
                  .read(themeControllerProvider.notifier)
                  .toggle(theme.brightness),
              icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF253D2E), Color(0xFF0D2225)],
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TODAY\'S SESSION',
                style: TextStyle(
                  color: Color(0xFFD6FF60),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'SHOW UP.\nGET STRONG.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  height: 1.02,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.6,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Full Body A · 5 exercises · ~45 min',
                style: TextStyle(color: Color(0xFFBED4C7)),
              ),
              const SizedBox(height: 26),
              FilledButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Workout tracking comes in the next phase.'),
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: NorthstarPalette.lime,
                  foregroundColor: const Color(0xFF102019),
                  minimumSize: const Size(double.infinity, 52),
                ),
                icon: const Icon(Icons.arrow_outward),
                label: const Text('Preview workout'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeading('Your health snapshot'),
        LayoutBuilder(
          builder: (context, limits) {
            final columns = limits.maxWidth >= 680 ? 4 : 2;
            final cards = [
              const _Metric('STEPS', '6,420', 'steps', Icons.directions_walk),
              const _Metric('SLEEP', '6h 18m', '', Icons.bedtime_outlined),
              const _Metric('RESTING HR', '58', 'bpm', Icons.favorite_border),
              const _Metric(
                'WEIGHT',
                '74.2',
                'kg',
                Icons.monitor_weight_outlined,
              ),
            ];
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cards.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 145,
              ),
              itemBuilder: (context, index) => cards[index],
            );
          },
        ),
        const SizedBox(height: 28),
        const SectionHeading('Consistency'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '2 of 3 sessions this week',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                const LinearProgressIndicator(value: 2 / 3, minHeight: 8),
                const SizedBox(height: 12),
                Text(
                  'Monday and Wednesday complete · demo',
                  style: TextStyle(
                    color: theme.extension<NorthstarColors>()!.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.name, this.value, this.unit, this.icon);

  final String name;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: theme.colorScheme.primary),
            const Spacer(),
            Text(
              name,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$value $unit',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              'Demo · Apple Health',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.extension<NorthstarColors>()!.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
