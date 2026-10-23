import 'package:flutter/material.dart';
import '../../core/design/section.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const DemoLabel(),
          const SizedBox(height: 8),
          Text('PROGRESS', style: Theme.of(context).textTheme.headlineLarge
              ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 28),
          const SectionHeading('Strength trend'),
          Card(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Squat · demo best set',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('60 kg', style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                const LinearProgressIndicator(value: 0.75, minHeight: 10),
                const SizedBox(height: 12),
                const Text('52.5 → 60 kg · 4 fictional sessions'),
              ],
            ),
          )),
          const SizedBox(height: 20),
          const Text('Detailed exercise history and period comparisons '
              'will become available with local workout persistence.'),
        ],
      );
}
