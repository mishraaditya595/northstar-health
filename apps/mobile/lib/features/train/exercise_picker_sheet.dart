import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/beyondrep_theme.dart';
import '../../core/design/dialogs.dart';
import '../../core/design/inputs.dart';
import '../../core/design/page_header.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/application/exercise_choices_provider.dart';
import '../catalog/data/catalog_repository.dart';
import '../catalog/domain/exercise_choices.dart';
import '../workouts/data/objectbox_workout_library_repository.dart';
import '../workouts/domain/workout_library_models.dart';
import 'train_library_state.dart';

const catalogUnavailableCopy =
    "The exercise library hasn't downloaded yet. "
    'Your own exercises and the basics still work.';

Future<void> retryCatalogDownload(WidgetRef ref) async {
  try {
    await ref.read(catalogRepositoryProvider).refresh(force: true);
  } on Object {
    // The status banner keeps showing; nothing else depends on this call.
  }
}

/// One picker over catalogue and local exercises. A catalogue exercise is
/// copied into this account's library when it is picked (idempotent); the
/// returned record is always the account's own local definition.
Future<ExerciseRecord?> showExercisePicker(
  BuildContext context,
  WidgetRef ref, {
  required String title,
}) async {
  final choice = await showNsSheet<ExerciseChoice>(
    context,
    heightFactor: 0.75,
    builder: (_) => _ExercisePickerBody(title: title),
  );
  if (choice == null || !context.mounted) return null;
  final catalog = choice.catalog;
  final release = choice.release;
  // Local-only exercises (custom, or built-ins the catalogue no longer lists)
  // are used as they are. A catalogue exercise is always passed through the
  // idempotent copy, using the release the user saw, so an older local copy
  // is refreshed and an up-to-date one is not written.
  if (catalog == null || release == null) return choice.local;
  try {
    final record = ref
        .read(workoutLibraryRepositoryProvider)
        .materializeCatalogExercise(
          id: catalog.id,
          name: catalog.name,
          muscleGroup: catalog.muscleGroup,
          equipment: choice.equipment,
          category: categoryLabel(catalog.category),
          mode: catalog.mode,
          release: release,
        );
    ref.invalidate(trainLibraryProvider);
    return record;
  } on Object {
    if (context.mounted) {
      showNsMessage(context, 'Could not add that exercise.');
    }
    return null;
  }
}

class _ExercisePickerBody extends ConsumerStatefulWidget {
  const _ExercisePickerBody({required this.title});

  final String title;

  @override
  ConsumerState<_ExercisePickerBody> createState() =>
      _ExercisePickerBodyState();
}

class _ExercisePickerBodyState extends ConsumerState<_ExercisePickerBody> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final choices = ref.watch(exerciseChoicesProvider);
    final status = safeCatalogState(() => ref.watch(catalogStateProvider))
        .status;
    final muted = Theme.of(context).extension<BeyondRepColors>()!.muted;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              NsTextField(
                onChanged: (text) => setState(() => query = text),
                prefixIcon: Icons.search,
                hint: 'Search exercises',
              ),
            ],
          ),
        ),
        Expanded(
          child: choices.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                const Center(child: Text('Exercise library could not load.')),
            data: (all) {
              final visible = all
                  .where((choice) => matchesExerciseQuery(choice, query))
                  .toList();
              // The status note scrolls with the list so large text never
              // squeezes the list out of a short sheet.
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (status == CatalogStatus.unavailable) ...[
                    Text(
                      catalogUnavailableCopy,
                      style: TextStyle(color: muted),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => retryCatalogDownload(ref),
                        child: const Text('Retry'),
                      ),
                    ),
                  ],
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: Text('No matching exercises.')),
                    ),
                  for (final choice in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: NsListCard(
                        icon: choice.isCustom
                            ? Icons.edit_note
                            : Icons.fitness_center,
                        title: choice.name,
                        subtitle: [
                          choice.muscleGroup,
                          choice.equipment,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        trailing: const Icon(Icons.add_circle_outline),
                        onTap: () => Navigator.pop(context, choice),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
