import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/clock.dart';
import '../../core/design/beyondrep_theme.dart';
import '../../core/design/dialogs.dart';
import '../../core/design/page_header.dart';
import '../../core/ids/uuid_factory.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/application/exercise_choices_provider.dart';
import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/catalog_programs.dart';
import '../catalog/domain/catalog_templates.dart';
import '../catalog/domain/exercise_choices.dart';
import '../programs/application/program_providers.dart';
import '../programs/data/objectbox_program_repository.dart';
import 'program_weekday_sheet.dart';
import 'workout_templates_page.dart' show levelLabel;

/// One program: the 7-day week with every day's prescriptions, and "Add
/// program".
class ProgramDetailPage extends ConsumerStatefulWidget {
  const ProgramDetailPage({required this.programId, super.key});

  final String programId;

  @override
  ConsumerState<ProgramDetailPage> createState() => _ProgramDetailPageState();
}

class _ProgramDetailPageState extends ConsumerState<ProgramDetailPage> {
  // One request UUID per add: a repeated tap reuses it (the repository
  // returns the same program) and a finished add makes a fresh one.
  var _request = SecureUuidFactory().newId();
  var _busy = false;
  final _expanded = <int>{};

  Future<void> _add(CatalogProgram program, CatalogSnapshot snapshot) async {
    if (_busy) return;
    final choice = await showProgramWeekdaySheet(
      context,
      title: 'Add ${program.name}',
      confirmLabel: 'Add program',
      initialWeekday: ref.read(localNowProvider).weekday,
      askActive: true,
    );
    if (choice == null || !mounted || _busy) return;
    _busy = true;
    setState(() {});
    // Let the disabled button paint before the (synchronous) write.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    try {
      final templates = {
        for (final id in program.week.whereType<String>())
          id: programTemplate(snapshot, id)!,
      };
      final created = ref
          .read(programRepositoryProvider)
          .importProgram(
            requestUuid: _request,
            program: program,
            templateRows: {
              for (final e in templates.entries)
                e.key: templateRowInputs(e.value, snapshot),
            },
            templateNames: {
              for (final e in templates.entries) e.key: e.value.name,
            },
            templateDescriptions: {
              for (final e in templates.entries) e.key: e.value.description,
            },
            release: snapshot.release,
            firstDayWeekday: choice.weekday,
            makeActive: choice.makeActive,
            localToday: ref.read(localNowProvider),
          );
      _request = SecureUuidFactory().newId();
      invalidatePrograms(ref);
      if (!mounted) return;
      showNsMessage(context, 'Added ${created.name}');
      context.pushReplacement('/train/program/${created.uuid}');
    } on Object {
      if (mounted) {
        showNsMessage(context, 'Could not add this program. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = safeCatalogState(() => ref.watch(catalogStateProvider))
        .snapshot;
    CatalogProgram? program;
    var retired = false;
    if (snapshot != null) {
      for (final p in browsablePrograms(snapshot)) {
        if (p.id == widget.programId) program = p;
      }
      retired = snapshot.programs.any(
        (p) => p.id == widget.programId && p.retired,
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const NsBackButton(),
        title: const Text('Program'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: program == null || snapshot == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    retired
                        ? 'This program is no longer available.'
                        : "This program isn't available.",
                  ),
                )
              : _body(context, program, snapshot),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    CatalogProgram program,
    CatalogSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    final names = {for (final e in snapshot.exercises) e.id: e.name};
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        28 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          program.name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(program.description, style: TextStyle(color: theme.mutedColor)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            NsTag(levelLabel(program.level)),
            NsTag('${program.daysPerWeek} days a week'),
            NsTag('about ${program.estimatedMinutes} min'),
            for (final label in equipmentLabel(program.equipment).split(', '))
              if (label.isNotEmpty) NsTag(label),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : () => _add(program, snapshot),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add program'),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < 7; i++)
          _day(context, i, program.week[i], snapshot, names),
        const SizedBox(height: 6),
        const InsightCard(
          icon: Icons.tips_and_updates_outlined,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'How to use this program',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(
                text:
                    '\nWarm up with lighter sets before the first heavy '
                    'exercise; only working sets are listed.'
                    '\nStop most sets with about 2 reps in reserve, and '
                    'keep your form.'
                    '\nAdd load only after every set of an exercise is '
                    'clean at the top of its rep range.'
                    '\nIf you miss reps or recover badly, repeat the same '
                    'load or lower it, and use fewer sets.'
                    '\nTimes are approximate and depend on your rest.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _day(
    BuildContext context,
    int index,
    String? templateId,
    CatalogSnapshot snapshot,
    Map<String, String> names,
  ) {
    final template = templateId == null
        ? null
        : programTemplate(snapshot, templateId);
    final open = _expanded.contains(index);
    final muted = Theme.of(context).mutedColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (template == null)
            NsListCard(
              icon: Icons.hotel_outlined,
              title: 'Day ${index + 1} · Rest',
              subtitle: 'No workout',
            )
          else
            NsListCard(
              icon: Icons.fitness_center,
              title:
                  'Day ${index + 1} · ${template.name} · '
                  '${template.exercises.length} exercises',
              subtitle: open ? 'Hide exercises' : 'Show exercises',
              trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
              onTap: () => setState(
                () => open ? _expanded.remove(index) : _expanded.add(index),
              ),
            ),
          if (template != null && open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in template.exercises)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            names[row.exerciseId] ?? row.exerciseId,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${prescriptionLabel(row)} · '
                            '${restLabel(row.restSeconds)}',
                            style: TextStyle(color: muted),
                          ),
                          if (row.note.isNotEmpty)
                            Text(row.note, style: TextStyle(color: muted)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
