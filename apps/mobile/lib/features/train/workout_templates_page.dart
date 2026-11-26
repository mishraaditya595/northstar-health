import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/beyondrep_theme.dart';
import '../../core/design/inputs.dart';
import '../../core/design/layout.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/application/exercise_choices_provider.dart';
import '../catalog/application/templates_provider.dart';
import '../catalog/data/catalog_repository.dart';
import '../catalog/domain/catalog_filter.dart';
import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/exercise_choices.dart';
import 'catalog_filter_sheet.dart';
import 'exercise_picker_sheet.dart';
import 'template_detail_page.dart';

const _levels = ['beginner', 'intermediate', 'advanced'];

String levelLabel(String level) =>
    level.isEmpty ? level : level[0].toUpperCase() + level.substring(1);

/// Equipment labels of a template, for list rows and the detail header.
String templateEquipment(CatalogTemplate template) =>
    equipmentLabel(template.equipment);

class WorkoutTemplatesPage extends ConsumerStatefulWidget {
  const WorkoutTemplatesPage({super.key});

  @override
  ConsumerState<WorkoutTemplatesPage> createState() =>
      _WorkoutTemplatesPageState();
}

class _WorkoutTemplatesPageState extends ConsumerState<WorkoutTemplatesPage> {
  CatalogFilter filter = const CatalogFilter();
  final searchController = TextEditingController();

  /// Wide windows: id of the item open in the detail pane.
  String? _selectedId;

  String _routeFor(String id) => '/train/workouts/${Uri.encodeComponent(id)}';

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
    return TemplateDetailPage(
      key: ValueKey(id),
      templateId: id,
      embedded: true,
    );
  }

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
        if (matchesTemplate(t, filter)) t,
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
        onChanged: (value) => setState(
          () => filter = filter.withQuery(value.trim().toLowerCase()),
        ),
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
              selected: filter.level == null,
              onSelected: (_) =>
                  setState(() => filter = filter.withLevel(null)),
            ),
            for (final name in _levels) ...[
              const SizedBox(width: 8),
              NsChip(
                label: levelLabel(name),
                selected: filter.level == name,
                onSelected: (on) =>
                    setState(() => filter = filter.withLevel(on ? name : null)),
              ),
            ],
          ],
        ),
      ),
      CatalogFilterSummary(
        filter: filter,
        onClear: () => setState(() => filter = filter.clearedSheetFilters()),
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
              onTap: () => openListItem(
                context,
                route: _routeFor(t.id),
                select: () => setState(() => _selectedId = t.id),
              ),
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
        actions: [
          CatalogFilterButton(
            onPressed: () async {
              final next = await showCatalogFilterSheet(
                context,
                filter: filter,
                goals: goalOptions([for (final t in all) t.goals]),
                equipment: equipmentFilterOptions([
                  for (final t in all) t.equipment,
                ]),
              );
              if (next != null && mounted) setState(() => filter = next);
            },
          ),
        ],
      ),
      body: NsListDetail(
        list: Center(
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
        detail: _detail((id) => all.any((t) => t.id == id)),
        emptyDetail: Center(
          child: Text(
            'Pick a workout to see every exercise.',
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
