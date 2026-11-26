import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/inputs.dart';
import '../../core/design/layout.dart';
import '../../core/design/dialogs.dart';
import '../../core/design/beyondrep_theme.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import '../../core/ids/uuid_factory.dart';
import '../../core/ui/dispose_after_dialog.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/application/exercise_choices_provider.dart';
import '../catalog/data/catalog_repository.dart';
import '../catalog/domain/exercise_choices.dart';
import '../catalog/domain/exercise_filter.dart';
import '../workouts/data/objectbox_workout_library_repository.dart';
import '../workouts/domain/workout_library_models.dart';
import 'exercise_filter_bar.dart';
import 'exercise_detail_page.dart';
import 'exercise_picker_sheet.dart';
import 'train_library_state.dart';

class ExerciseCatalogPage extends ConsumerStatefulWidget {
  const ExerciseCatalogPage({super.key});

  @override
  ConsumerState<ExerciseCatalogPage> createState() =>
      _ExerciseCatalogPageState();
}

class _ExerciseCatalogPageState extends ConsumerState<ExerciseCatalogPage> {
  String query = '';
  final searchController = TextEditingController();
  bool customOnly = false;

  /// Wide windows: id of the item open in the detail pane.
  String? _selectedId;

  String _routeFor(String id) => '/train/exercises/${Uri.encodeComponent(id)}';

  /// The pane's page, or null (clearing the selection) when the item is gone.
  Widget? _detail(bool Function(String id) exists) {
    final id = _selectedId;
    if (id == null) return null;
    if (!exists(id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedId == id) setState(() => _selectedId = null);
      });
      return null;
    }
    return ExerciseDetailPage(
      key: ValueKey(id),
      exerciseId: id,
      embedded: true,
    );
  }

  String? group;
  String? equipment;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _edit(ExerciseRecord? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final muscle = TextEditingController(text: existing?.muscleGroup ?? '');
    final equipment = TextEditingController(text: existing?.equipment ?? '');
    String? error;
    try {
      await showNsDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => NsDialog(
            title: existing == null ? 'New exercise' : 'Edit exercise',
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NsTextField(
                      controller: name,
                      autofocus: true,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.sentences,
                      label: 'Exercise name *',
                    ),
                    const SizedBox(height: 8),
                    NsTextField(
                      controller: muscle,
                      maxLength: 60,
                      label: 'Muscle group',
                    ),
                    const SizedBox(height: 8),
                    NsTextField(
                      controller: equipment,
                      maxLength: 60,
                      label: 'Equipment',
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  try {
                    ref
                        .read(workoutLibraryRepositoryProvider)
                        .saveCustomExercise(
                          uuid: existing?.uuid ?? SecureUuidFactory().newId(),
                          name: name.text,
                          muscleGroup: muscle.text,
                          equipment: equipment.text,
                          expectedUpdatedAtMs: existing?.updatedAtMs,
                        );
                    ref.invalidate(trainLibraryProvider);
                    Navigator.pop(dialogContext);
                  } catch (_) {
                    setDialogState(
                      () => error = 'Could not save. Check the name, duplicates or an older edit.',
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
    } finally {
      disposeAfterDialog([name, muscle, equipment]);
    }
  }

  Future<void> _archive(ExerciseRecord exercise) async {
    final confirm = await showNsConfirm(
      context,
      title: 'Archive exercise?',
      message:
          'Remove "${exercise.name}" from your library? '
          'It will remain in existing plans and workout history.',
      confirmLabel: 'Archive',
    );
    if (!confirm || !mounted) return;
    try {
      ref
          .read(workoutLibraryRepositoryProvider)
          .archiveCustomExercise(exercise.uuid);
      ref.invalidate(trainLibraryProvider);
    } catch (_) {
      if (mounted) {
        showNsMessage(context, 'Could not archive that exercise.');
      }
    }
  }

  Future<void> _refreshCatalog() async {
    var outcome = CatalogRefreshOutcome.failed;
    try {
      outcome = await ref.read(catalogRepositoryProvider).refresh(force: true);
    } on Object {
      // Handled as a failed refresh below.
    }
    const failures = {
      CatalogRefreshOutcome.invalid,
      CatalogRefreshOutcome.failed,
      CatalogRefreshOutcome.notLive,
      CatalogRefreshOutcome.unauthorized,
    };
    if (failures.contains(outcome) && mounted) {
      final hasCopy =
          safeCatalogState(() => ref.read(catalogStateProvider)).snapshot !=
          null;
      showNsMessage(
        context,
        hasCopy
            ? "Couldn't update the exercise library. Showing the saved copy."
            : "Couldn't download the exercise library. "
                  'Check your connection and try again.',
      );
    }
  }

  Widget _row(ExerciseChoice choice) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: NsListCard(
      onTap: () => openListItem(
        context,
        route: _routeFor(choice.id),
        select: () => setState(() => _selectedId = choice.id),
      ),
      icon: choice.isCustom ? Icons.edit_note : Icons.fitness_center,
      title: choice.name,
      subtitle: [
        choice.muscleGroup,
        choice.equipment,
      ].where((s) => s.isNotEmpty).join(' · '),
      trailing: !choice.isCustom
          ? const NsTag('Built-in')
          : PopupMenuButton<String>(
              tooltip: 'Exercise actions for ${choice.name}',
              onSelected: (action) {
                if (action == 'edit') {
                  _edit(choice.local);
                }
                if (action == 'archive') {
                  _archive(choice.local!);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'archive', child: Text('Archive')),
              ],
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(exerciseChoicesProvider);
    final status = safeCatalogState(() => ref.watch(catalogStateProvider))
        .status;
    final muted = Theme.of(context).extension<BeyondRepColors>()!.muted;
    final all = async.asData?.value ?? const <ExerciseChoice>[];
    final equipmentChoices = equipmentOptions(all);
    final filter = ExerciseFilter(
      group: group,
      equipment: equipmentChoices.contains(equipment) ? equipment : null,
    );
    final headers = <Widget>[
      const SectionHeading('Find your movement'),
      Text(
        'Built-ins are read-only. Your own exercises stay on this device.',
        style: TextStyle(color: muted),
      ),
      if (status == CatalogStatus.unavailable) ...[
        const SizedBox(height: 8),
        Text(catalogUnavailableCopy, style: TextStyle(color: muted)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => retryCatalogDownload(ref),
            child: const Text('Retry'),
          ),
        ),
      ],
      if (status == CatalogStatus.outdatedApp) ...[
        const SizedBox(height: 8),
        Text(
          'Update BeyondRep to get the latest exercises.',
          style: TextStyle(color: muted),
        ),
      ],
      const SizedBox(height: 16),
      NsTextField(
        controller: searchController,
        onChanged: (value) =>
            setState(() => query = value.trim().toLowerCase()),
        prefixIcon: Icons.search,
        hint: 'Search exercise or equipment',
      ),
      const SizedBox(height: 12),
      ExerciseFilterBar(
        group: group,
        equipment: equipment,
        equipmentChoices: equipmentChoices,
        onGroup: (value) => setState(() => group = value),
        onEquipment: (value) => setState(() => equipment = value),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: NsChip(
          label: 'Custom only',
          selected: customOnly,
          onSelected: (value) => setState(() => customOnly = value),
        ),
      ),
      const SizedBox(height: 14),
    ];
    final visible = all
        .where(
          (choice) =>
              (!customOnly || choice.isCustom) &&
              filter.matches(choice) &&
              matchesExerciseQuery(choice, query),
        )
        .toList();
    // One builder per row below the header, so a long library builds lazily.
    final rows = <WidgetBuilder>[
      if (!async.hasValue && async.isLoading)
        (_) => const Center(child: CircularProgressIndicator())
      else if (!async.hasValue && async.hasError)
        (_) => TextButton(
          onPressed: () => ref.invalidate(trainLibraryProvider),
          child: const Text('Could not load exercises. Retry'),
        )
      else if (visible.isEmpty)
        (_) => const Padding(
          padding: EdgeInsets.all(20),
          child: Text('No matching exercises.'),
        )
      else
        for (final choice in visible) (_) => _row(choice),
    ];
    return Scaffold(
      appBar: AppBar(
        leading: const NsBackButton(),
        title: const Text('Exercise library'),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: FloatingActionButton.extended(
          onPressed: () => _edit(null),
          icon: const Icon(Icons.add),
          label: const Text('Custom exercise'),
        ),
      ),
      body: NsListDetail(
        list: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: RefreshIndicator(
              onRefresh: _refreshCatalog,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  100 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: headers.length + rows.length,
                itemBuilder: (context, index) => index < headers.length
                    ? headers[index]
                    : rows[index - headers.length](context),
              ),
            ),
          ),
        ),
        detail: _detail((id) => !async.hasValue || all.any((c) => c.id == id)),
        emptyDetail: Center(
          child: Text(
            'Pick an exercise to see how it\'s done.',
            style: TextStyle(color: muted),
          ),
        ),
        selectedRoute: _selectedId == null ? null : _routeFor(_selectedId!),
        onCollapsed: (route) {
          setState(() => _selectedId = null);
          context.push(route);
        },
      ),
    );
  }
}
