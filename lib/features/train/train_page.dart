import 'package:flutter/material.dart';
import '../../core/design/section.dart';

class TrainPage extends StatelessWidget {
  const TrainPage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const DemoLabel(),
          const SizedBox(height: 8),
          Text('TRAIN', style: Theme.of(context).textTheme.headlineLarge
              ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 28),
          const SectionHeading('Training plan'),
          Card(child: ListTile(
            contentPadding: const EdgeInsets.all(18),
            leading: const Icon(Icons.fitness_center),
            title: const Text('Full Body A'),
            subtitle: const Text('Squat · Bench press · Seated row · RDL · Plank'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Plan editing is not yet implemented.')),
            ),
          )),
          const SizedBox(height: 24),
          const SectionHeading('Built for progress'),
          const Text('Your custom plans, sets and rest timers will live here. '
              'The first native release will persist workouts offline.'),
        ],
      );
}
