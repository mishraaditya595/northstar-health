import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/beyondrep_theme.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import '../catalog/application/exercise_choices_provider.dart';
import '../catalog/domain/exercise_choices.dart';
import '../progress/muscle_map.dart';
import '../progress/muscle_recovery.dart';
import '../workouts/domain/muscles.dart';
import 'train_library_state.dart';

/// One exercise: its muscles on the body map, equipment, category, input mode
/// and technique cues. Custom exercises have no muscle mapping yet.
class ExerciseDetailPage extends ConsumerWidget {
  const ExerciseDetailPage({
    required this.exerciseId,
    this.embedded = false,
    super.key,
  });

  final String exerciseId;

  /// Shown inside the exercise list's detail pane: no back button.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(exerciseChoicesProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: embedded ? null : const NsBackButton(),
        title: const Text('Exercise'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(trainLibraryProvider),
                child: const Text('Could not load this exercise. Retry'),
              ),
            ),
            data: (choices) {
              ExerciseChoice? choice;
              for (final c in choices) {
                if (c.id == exerciseId) choice = c;
              }
              if (choice == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text("This exercise isn't available."),
                );
              }
              return _Detail(choice: choice);
            },
          ),
        ),
      ),
    );
  }
}

String _modeLabel(String mode) => switch (mode) {
  'reps_load' => 'Reps and weight',
  'duration' => 'Time',
  _ => mode,
};

class _Detail extends StatelessWidget {
  const _Detail({required this.choice});

  final ExerciseChoice choice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.mutedColor;
    final catalog = choice.catalog;
    final primary =
        catalog?.primaryMuscles ?? choice.local?.primaryMuscles ?? [];
    final secondary =
        catalog?.secondaryMuscles ?? choice.local?.secondaryMuscles ?? [];
    final mapped = primary.isNotEmpty;
    final category = catalog != null
        ? categoryLabel(catalog.category)
        : choice.local?.movementCategory ?? '';
    final cues = catalog?.cues ?? const <String>[];
    final recovery = MuscleRecovery({
      for (final name in secondary)
        ?muscleFromName(name): secondaryMuscleWeight,
      for (final name in primary) ?muscleFromName(name): 1.0,
    });

    final bodyMapLabel =
        'Body map: ${primary.map(muscleDisplayName).join(', ')}'
        '${secondary.isEmpty ? '' : '; secondary ${secondary.map(muscleDisplayName).join(', ')}'}';

    Widget facts(String label, String value) => value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(label, style: TextStyle(color: muted)),
                ),
                Expanded(child: Text(value)),
              ],
            ),
          );

    Widget muscleList(String title, List<String> names) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: muted,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final n in names) NsTag(muscleDisplayName(n))],
          ),
        ],
      ),
    );

    Widget figure(BodySide side, String label) => Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 170),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MuscleMap(side: side, recovery: recovery),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: muted,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Semantics(header: true, child: SectionHeading(choice.name)),
        if (choice.aliases.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              choice.aliases.join(' · '),
              style: TextStyle(color: muted),
            ),
          ),
        if (mapped) ...[
          muscleList('Primary', primary),
          if (secondary.isNotEmpty) muscleList('Secondary', secondary),
          Semantics(
            label: bodyMapLabel,
            excludeSemantics: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                figure(BodySide.front, 'FRONT'),
                const SizedBox(width: 16),
                figure(BodySide.back, 'BACK'),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              choice.isCustom
                  ? "Custom exercise. Muscles aren't mapped yet."
                  : "Muscles aren't mapped yet.",
              style: TextStyle(color: muted),
            ),
          ),
        facts('Group', mapped ? '' : choice.muscleGroup),
        facts('Equipment', choice.equipment),
        facts('Category', category),
        facts('Mode', choice.isCustom ? '' : _modeLabel(choice.mode)),
        if (cues.isNotEmpty) ...[
          const SizedBox(height: 14),
          const SectionHeading('Technique'),
          for (final cue in cues)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(cue)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
