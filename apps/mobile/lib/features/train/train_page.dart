import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/northstar_theme.dart';
import '../../core/design/section.dart';
import '../workouts/domain/workout_library_models.dart';
import 'active_workout_state.dart';
import 'train_library_state.dart';

class TrainPage extends ConsumerWidget {
  const TrainPage({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, String route) async {
    await context.push<void>(route);
    ref.invalidate(trainLibraryProvider);
  }

  Future<void> _startQuick(BuildContext context, WidgetRef ref) async {
    var proposed = 'Quick workout';
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start an empty workout'),
        content: TextFormField(
          autofocus: true,
          initialValue: proposed,
          onChanged: (value) => proposed = value,
          maxLength: 160,
          decoration: const InputDecoration(labelText: 'Workout name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, proposed.trim()),
            child: const Text('Start workout'),
          ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    if (chosen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a workout name first.')),
      );
      return;
    }
    _start(
      context,
      ref,
      () => ref.read(workoutActionsProvider).startQuick(chosen),
    );
  }

  void _startPlan(BuildContext context, WidgetRef ref, String uuid) {
    _start(
      context,
      ref,
      () => ref.read(workoutActionsProvider).startPlan(uuid),
    );
  }

  void _start(BuildContext context, WidgetRef ref, void Function() action) {
    try {
      action();
      ref.invalidate(activeWorkoutProvider);
      context.push('/train/workout');
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not start this workout. Check the plan and any unfinished workout.',
          ),
        ),
      );
      ref.invalidate(activeWorkoutProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trainLibraryProvider);
    final colors = Theme.of(context).extension<NorthstarColors>()!;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
          children: [
            Text(
              'TRAIN',
              style: Theme.of(context).textTheme.headlineLarge
                  ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1.2),
            ),
            const SizedBox(height: 8),
            Text(
              'Own your training. Your plans stay on this device.',
              style: TextStyle(color: colors.muted),
            ),
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
                    Text(
                      'BUILD THE WORK.',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Build a plan or start recording reps and weights offline.',
                      style: TextStyle(color: colors.muted),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => _startQuick(context, ref),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Quick workout'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _open(context, ref, '/train/plans/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Create training plan'),
                    ),
                  ],
                ),
              ),
            ),
            Consumer(
              builder: (context, ref, _) {
                final current = ref.watch(activeWorkoutProvider);
                return current.when(
                  loading: () => const SizedBox(
                    height: 32,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Text(
                            'Workout recovery needs attention. '
                            'No local data has been deleted.',
                          ),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(activeWorkoutProvider),
                            child: const Text('Retry recovery'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  data: (view) => view == null
                      ? const SizedBox.shrink()
                      : Card(
                          child: ListTile(
                            leading: const Icon(Icons.restore),
                            title: Text('Resume: ${view.session.name}'),
                            subtitle: Text(
                              view.session.status.name == 'paused'
                                  ? 'Paused workout saved on this device'
                                  : 'Unfinished workout saved on this device',
                            ),
                            trailing: const Icon(Icons.arrow_forward),
                            onTap: () => context.push('/train/workout'),
                          ),
                        ),
                );
              },
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                const Expanded(child: SectionHeading('Your plans')),
                TextButton.icon(
                  onPressed: () => _open(context, ref, '/train/exercises'),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Exercise library'),
                ),
              ],
            ),
            state.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (_, _) => Column(
                children: [
                  const Text('Could not load your local training plans.'),
                  TextButton(
                    onPressed: () => ref.invalidate(trainLibraryProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
              data: (snapshot) => _planList(context, ref, snapshot),
            ),
            const SizedBox(height: 20),
            Text(
              'LOCAL ONLY · NO ACCOUNT REQUIRED',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.muted,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planList(
    BuildContext context,
    WidgetRef ref,
    WorkoutLibrarySnapshot data,
  ) {
    if (data.plans.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No plans yet',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Make a plan with your favourite exercises, sets, and rep targets.',
              ),
            ],
          ),
        ),
      );
    }
    final labels = <String, String>{
      for (final exercise in data.exercises) exercise.uuid: exercise.name,
    };
    return Column(
      children: [
        for (final plan in data.plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                minVerticalPadding: 14,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                title: Text(
                  plan.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    plan.exercises.isEmpty
                        ? 'No exercises added'
                        : plan.exercises
                              .map(
                                (e) =>
                                    labels[e.exerciseUuid] ??
                                    'Archived exercise',
                              )
                              .take(3)
                              .join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Start ${plan.name}',
                      icon: const Icon(Icons.play_circle_fill),
                      onPressed: () => _startPlan(context, ref, plan.uuid),
                    ),
                    IconButton(
                      tooltip: 'Edit ${plan.name}',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () =>
                          _open(context, ref, '/train/plans/${plan.uuid}/edit'),
                    ),
                  ],
                ),
                onTap: () =>
                    _open(context, ref, '/train/plans/${plan.uuid}/edit'),
              ),
            ),
          ),
      ],
    );
  }
}
