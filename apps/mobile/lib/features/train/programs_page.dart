import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/beyondrep_theme.dart';
import '../../core/design/inputs.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/application/exercise_choices_provider.dart';
import '../catalog/data/catalog_repository.dart';
import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/exercise_choices.dart';
import '../programs/application/program_providers.dart';
import 'exercise_picker_sheet.dart';
import 'workout_templates_page.dart' show levelLabel;

const _levels = ['beginner', 'intermediate', 'advanced'];

bool _matches(CatalogProgram program, String query, String? level) {
  if (level != null && program.level != level) return false;
  if (query.isEmpty) return true;
  return program.name.toLowerCase().contains(query) ||
      program.description.toLowerCase().contains(query);
}

/// "3 days a week · Beginner · about 45 min".
String programSummary(CatalogProgram p) =>
    '${p.daysPerWeek} ${p.daysPerWeek == 1 ? 'day' : 'days'} a week · '
    '${levelLabel(p.level)} · about ${p.estimatedMinutes} min';

class ProgramsPage extends ConsumerStatefulWidget {
  const ProgramsPage({super.key});

  @override
  ConsumerState<ProgramsPage> createState() => _ProgramsPageState();
}

class _ProgramsPageState extends ConsumerState<ProgramsPage> {
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
    final all = ref.watch(catalogProgramsProvider);
    final mine = ref.watch(localProgramsProvider);
    final status = safeCatalogState(() => ref.watch(catalogStateProvider))
        .status;
    final muted = Theme.of(context).extension<BeyondRepColors>()!.muted;
    final visible = [
      for (final p in all)
        if (_matches(p, query, level)) p,
    ];
    final headers = <Widget>[
      if (mine.isNotEmpty) ...[
        const SectionHeading('Your programs'),
        for (final p in mine)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NsListCard(
              onTap: () => context.push('/train/program/${p.uuid}'),
              icon: Icons.event_repeat_outlined,
              title: p.name,
              subtitle: p.isActive ? 'Active' : 'Not active',
            ),
          ),
        const SizedBox(height: 8),
      ],
      const SectionHeading('Programs'),
      Text(
        'A weekly schedule of workouts. Add one to get plans you can edit.',
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
        hint: 'Search programs',
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
                : 'No matching programs.',
          ),
        )
      else
        for (final p in visible)
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NsListCard(
              onTap: () =>
                  context.push('/train/programs/${Uri.encodeComponent(p.id)}'),
              icon: Icons.event_repeat_outlined,
              title: p.name,
              subtitle: '${programSummary(p)}\n${equipmentLabel(p.equipment)}',
            ),
          ),
    ];
    return Scaffold(
      appBar: AppBar(
        leading: const NsBackButton(),
        title: const Text('Programs'),
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
