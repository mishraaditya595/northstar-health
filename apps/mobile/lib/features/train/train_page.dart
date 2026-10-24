import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/northstar_theme.dart';
import '../../core/design/section.dart';
import '../workouts/domain/workout_library_models.dart';
import 'train_library_state.dart';

class TrainPage extends ConsumerWidget {
  const TrainPage({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, String route) async {
    await context.push<void>(route);
    ref.invalidate(trainLibraryProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trainLibraryProvider);
    final colors = Theme.of(context).extension<NorthstarColors>()!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
      children: [
        Text('TRAIN', style: Theme.of(context).textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w900, letterSpacing: -1.2)),
        const SizedBox(height: 8),
        Text('Own your training. Your plans stay on this device.',
          style: TextStyle(color: colors.muted)),
        const SizedBox(height: 24),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.fitness_center_rounded, size: 32),
                const SizedBox(height: 12),
                Text('BUILD THE WORK.', style: Theme.of(context)
                    .textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text('Create a repeatable training session. Logging live sets comes next.',
                    style: TextStyle(color: colors.muted)),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => _open(context, ref, '/train/plans/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Create training plan'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        Row(children: [
          const Expanded(child: SectionHeading('Your plans')),
          TextButton.icon(
            onPressed: () => _open(context, ref, '/train/exercises'),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Exercise library'),
          ),
        ]),
        state.when(
          loading: () => const Center(child: Padding(
            padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
          error: (_, _) => Column(children: [
            const Text('Could not load your local training plans.'),
            TextButton(
              onPressed: () => ref.invalidate(trainLibraryProvider),
              child: const Text('Retry'),
            ),
          ]),
          data: (snapshot) => _planList(context, ref, snapshot),
        ),
        const SizedBox(height: 20),
        Text('LOCAL ONLY · NO ACCOUNT REQUIRED',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.muted, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _planList(BuildContext context, WidgetRef ref, WorkoutLibrarySnapshot data) {
    if (data.plans.isEmpty) {
      return Card(child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('No plans yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Make a plan with your favourite exercises, sets, and rep targets.'),
        ]),
      ));
    }
    final labels = <String, String>{
      for (final exercise in data.exercises) exercise.uuid: exercise.name,
    };
    return Column(children: [
      for (final plan in data.plans)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              minVerticalPadding: 14,
              contentPadding: const EdgeInsets.symmetric(horizontal: 18),
              title: Text(plan.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(plan.exercises.isEmpty
                  ? 'No exercises added'
                  : plan.exercises.map((e) => labels[e.exerciseUuid] ?? 'Archived exercise')
                      .take(3).join(' · '),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, ref, '/train/plans/${plan.uuid}/edit'),
            ),
          ),
        ),
    ]);
  }
}
