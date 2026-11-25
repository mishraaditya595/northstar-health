import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/clock.dart';
import '../../core/date_labels.dart';
import '../../core/design/dialogs.dart';
import '../../core/design/inputs.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import '../health/widgets/readiness_note.dart';
import '../programs/application/program_providers.dart';
import '../programs/data/objectbox_program_repository.dart';
import '../programs/domain/program_models.dart';
import '../programs/domain/program_repository.dart';
import '../programs/domain/program_schedule.dart';
import '../workouts/data/objectbox_workout_library_repository.dart';
import 'active_workout_state.dart';
import 'program_weekday_sheet.dart';

const _rest = '';

/// A program the user added: today's workout, the weekly schedule and its
/// editing, and activation and archive.
class MyProgramPage extends ConsumerStatefulWidget {
  const MyProgramPage({required this.programUuid, super.key});

  final String programUuid;

  @override
  ConsumerState<MyProgramPage> createState() => _MyProgramPageState();
}

class _MyProgramPageState extends ConsumerState<MyProgramPage> {
  var _busy = false;

  String _planName(String planUuid) =>
      ref.read(workoutLibraryRepositoryProvider).getPlan(planUuid)?.name ??
      'Workout';

  void _failed(String message) => showNsMessage(context, message);

  Future<void> _start(TrainingProgramRecord program) async {
    if (_busy) return;
    _busy = true;
    setState(() {});
    try {
      final active = ref.read(activeWorkoutProvider);
      if (active.value != null || active.hasError) {
        _startFailed();
        return;
      }
      if (!await confirmReadinessBeforeStart(context, ref) || !mounted) {
        return;
      }
      try {
        ref
            .read(workoutActionsProvider)
            .startProgramDay(program, ref.read(localNowProvider));
        ref.invalidate(activeWorkoutProvider);
        invalidatePrograms(ref);
      } on Object {
        _startFailed();
        return;
      }
      await context.push<void>('/train/workout');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startFailed() {
    _failed(
      'Could not start this workout. Check the plan and any unfinished '
      'workout.',
    );
    ref.invalidate(activeWorkoutProvider);
  }

  void _write(void Function(ProgramRepository) action) {
    try {
      action(ref.read(programRepositoryProvider));
    } on Object {
      _failed('Could not save this change. Try again.');
    }
    invalidatePrograms(ref);
  }

  Future<void> _editDay(
    TrainingProgramRecord program,
    ({int weekday, ProgramDayRecord day}) entry,
  ) async {
    final plans = <String>{for (final d in program.days) ?d.planUuid}.toList();
    final current = entry.day.planUuid ?? _rest;
    final result = await showNsSheet<(String, String)>(
      context,
      heightFactor: 0.55,
      builder: (sheetContext) => ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          20 + MediaQuery.paddingOf(sheetContext).bottom,
        ),
        children: [
          Text(
            weekdayNames[entry.weekday - 1],
            style: Theme.of(sheetContext).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          if (entry.day.planUuid != null) ...[
            FilledButton.icon(
              onPressed: () =>
                  Navigator.pop(sheetContext, ('edit', entry.day.planUuid!)),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit workout'),
            ),
            const SizedBox(height: 14),
          ],
          NsDropdown<String>(
            label: 'Change to…',
            value: current,
            options: [
              for (final uuid in plans) NsOption(uuid, _planName(uuid)),
              const NsOption(_rest, 'Rest'),
            ],
            onChanged: (value) {
              if (value != current) Navigator.pop(sheetContext, ('set', value));
            },
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    if (result.$1 == 'edit') {
      await context.push<void>('/train/plans/${result.$2}/edit');
      if (mounted) invalidatePrograms(ref);
      return;
    }
    _write(
      (repo) => repo.setDayPlan(
        program.uuid,
        entry.day.dayIndex,
        result.$2.isEmpty ? null : result.$2,
      ),
    );
  }

  Future<void> _changeStartDay(TrainingProgramRecord program) async {
    final choice = await showProgramWeekdaySheet(
      context,
      title: 'Change start day',
      confirmLabel: 'Save',
      initialWeekday: program.firstDayWeekday,
    );
    if (choice == null || !mounted) return;
    _write((repo) => repo.setFirstWeekday(program.uuid, choice.weekday));
  }

  Future<void> _archive(TrainingProgramRecord program) async {
    final yes = await showNsConfirm(
      context,
      title: 'Archive this program?',
      message:
          'Its workouts are archived with it. Workouts you already logged '
          'stay in your history.',
      confirmLabel: 'Archive',
    );
    if (!yes || !mounted) return;
    try {
      ref
          .read(programRepositoryProvider)
          .archiveProgram(
            program.uuid,
            DateTime.now().toUtc().millisecondsSinceEpoch,
          );
    } on Object {
      _failed('Could not archive this program.');
      return;
    }
    invalidatePrograms(ref);
    if (!mounted) return;
    showNsMessage(context, 'Program archived');
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/train');
    }
  }

  @override
  Widget build(BuildContext context) {
    final program = ref.watch(localProgramProvider(widget.programUuid));
    final now = ref.watch(localNowProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const NsBackButton(),
        title: const Text('Your program'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: program == null
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text("This program isn't available."),
                )
              : _body(context, program, now),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    TrainingProgramRecord program,
    DateTime now,
  ) {
    final theme = Theme.of(context);
    final todayIndex = programDayIndex(now, program.firstDayWeekday);
    final todayPlan = dayFor(program, now).planUuid;
    final week = calendarWeek(program);
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [NsTag(program.isActive ? 'Active' : 'Not active')],
        ),
        const SizedBox(height: 16),
        if (todayPlan == null)
          Text(
            'Rest day today',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          )
        else
          FilledButton.icon(
            onPressed: _busy ? null : () => _start(program),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text("Start today's workout"),
          ),
        const SizedBox(height: 20),
        const SectionHeading('This week'),
        if (week.every((e) => e.day.planUuid == null))
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('No training days'),
          ),
        for (final entry in week)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NsListCard(
              onTap: () => _editDay(program, entry),
              icon: entry.day.planUuid == null
                  ? Icons.hotel_outlined
                  : Icons.fitness_center,
              title:
                  '${weekdayNames[entry.weekday - 1]} · '
                  '${entry.day.planUuid == null ? 'Rest' : _planName(entry.day.planUuid!)}',
              subtitle:
                  'Day ${entry.day.dayIndex + 1}'
                  '${entry.day.dayIndex == todayIndex ? ' · Today' : ''}',
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => _changeStartDay(program),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          child: const Text('Change start day'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _write(
            (repo) => repo.setActive(program.uuid, !program.isActive, now),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          child: Text(
            program.isActive ? 'Stop using this program' : 'Make active',
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => _archive(program),
          style: TextButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          child: const Text('Archive program'),
        ),
      ],
    );
  }
}
