import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/beyondrep_theme.dart';
import '../../core/design/inputs.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/application/exercise_choices_provider.dart';
import '../catalog/application/templates_provider.dart';
import '../catalog/data/catalog_repository.dart';
import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/exercise_choices.dart';
import 'exercise_picker_sheet.dart';

const _levels = ['beginner', 'intermediate', 'advanced'];

String levelLabel(String level) =>
    level.isEmpty ? level : level[0].toUpperCase() + level.substring(1);

/// Equipment labels of a template, for list rows and the detail header.
String templateEquipment(CatalogTemplate template) =>
    equipmentLabel(template.equipment);

bool _matches(CatalogTemplate template, String query, String? level) {
  if (level != null && template.level != level) return false;
  if (query.isEmpty) return true;
  return template.name.toLowerCase().contains(query) ||
      template.description.toLowerCase().contains(query);
}

class WorkoutTemplatesPage extends ConsumerStatefulWidget {
  const WorkoutTemplatesPage({super.key});

  @override
  ConsumerState<WorkoutTemplatesPage> createState() =>
      _WorkoutTemplatesPageState();
}

class _WorkoutTemplatesPageState extends ConsumerState<WorkoutTemplatesPage> {
  String query = '';
  String? level;
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await ref.read(catalogRepositoryProvider).refresh(force: true);
    } on Object {
      // The status text below keeps showing; nothing else depends on this.
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(templatesProvider);
    final status = safeCatalogState(() => ref.watch(catalogStateProvider))
        .status;
    final muted = Theme.of(context).extension<BeyondRepColors>()!.muted;
    final visible = [
      for (final t in all)
        if (_matches(t, query, level)) t,
    ];
    final headers = <Widget>[
      const SectionHeading('Ready-made workouts'),
      Text(
        'Start one now, or copy it into My Plans to make it your own.',
        style: TextStyle(color: muted),
      ),
      if (status == CatalogStatus.unavailable && all.isEmpty) ...[
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
        hint: 'Search workouts',
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            NsChip(
              label: 'All',
              selected: level == null,
              onSelected: (_) => setState(() => level = null),
            ),
            for (final name in _levels) ...[
              const SizedBox(width: 8),
              NsChip(
                label: levelLabel(name),
                selected: level == name,
                onSelected: (on) => setState(() => level = on ? name : null),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
    ];
    final rows = <WidgetBuilder>[
      if (visible.isEmpty)
        (_) => Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            all.isEmpty && status != CatalogStatus.ready
                ? ''
                : 'No matching workouts.',
          ),
        )
      else
        for (final t in visible)
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NsListCard(
              onTap: () =>
                  context.push('/train/workouts/${Uri.encodeComponent(t.id)}'),
              icon: Icons.view_list_outlined,
              title: t.name,
              subtitle:
                  '${levelLabel(t.level)} · ${t.estimatedMinutes} min · '
                  '${t.exercises.length} exercises\n${templateEquipment(t)}',
            ),
          ),
    ];
    return Scaffold(
      appBar: AppBar(
        leading: const NsBackButton(),
        title: const Text('Workouts'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                28 + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: headers.length + rows.length,
              itemBuilder: (context, index) => index < headers.length
                  ? headers[index]
                  : rows[index - headers.length](context),
            ),
          ),
        ),
      ),
    );
  }
}
