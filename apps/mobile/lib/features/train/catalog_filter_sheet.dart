import 'package:flutter/material.dart';

import '../../core/design/dialogs.dart';
import '../../core/design/inputs.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import '../catalog/domain/catalog_filter.dart';
import '../catalog/domain/exercise_choices.dart';

/// Opens the goal, equipment and (for programs) days-per-week filters. Returns
/// the new filter after "Show results", or null when the sheet is dismissed.
Future<CatalogFilter?> showCatalogFilterSheet(
  BuildContext context, {
  required CatalogFilter filter,
  required List<String> goals,
  required List<String> equipment,
  bool showDays = false,
}) => showNsSheet<CatalogFilter>(
  context,
  heightFactor: 0.85,
  builder: (sheetContext) => _FilterSheet(
    initial: filter,
    goals: goals,
    equipment: equipment,
    showDays: showDays,
  ),
);

/// Days-per-week choices.
const programDayChoices = [2, 3, 4, 5, 6];

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.goals,
    required this.equipment,
    required this.showDays,
  });

  final CatalogFilter initial;
  final List<String> goals;
  final List<String> equipment;
  final bool showDays;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late CatalogFilter draft = widget.initial;

  Widget _group(String title, List<Widget> chips, {String? note}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeading(title),
      if (note != null)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(note)),
      Wrap(spacing: 8, runSpacing: 8, children: chips),
      const SizedBox(height: 16),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          'Filters',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (widget.goals.isNotEmpty)
          _group('Goal', [
            for (final goal in widget.goals)
              NsChip(
                label: goalLabel(goal),
                selected: draft.goals.contains(goal),
                onSelected: (_) =>
                    setState(() => draft = draft.toggleGoal(goal)),
              ),
          ]),
        if (widget.equipment.isNotEmpty)
          _group(
            'Equipment I have',
            [
              for (final id in widget.equipment)
                NsChip(
                  label: equipmentLabel([id]),
                  selected: draft.equipment.contains(id),
                  onSelected: (_) =>
                      setState(() => draft = draft.toggleEquipment(id)),
                ),
            ],
            note: 'Bodyweight always counts. Choose nothing to see everything.',
          ),
        if (widget.showDays)
          _group('Days per week', [
            for (final days in programDayChoices)
              NsChip(
                label: '$days',
                selected: draft.daysPerWeek == days,
                onSelected: (_) => setState(() => draft = draft.withDays(days)),
              ),
          ]),
        FilledButton(
          onPressed: () => Navigator.pop(context, draft),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          child: const Text('Show results'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => draft = draft.clearedSheetFilters()),
          style: TextButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          child: const Text('Clear'),
        ),
      ],
    );
  }
}

/// The header button that opens the filter sheet.
class CatalogFilterButton extends StatelessWidget {
  const CatalogFilterButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: SquareButton(
      tooltip: 'Filters',
      onPressed: onPressed,
      child: const Icon(Icons.tune, size: 20),
    ),
  );
}

/// "Filters (2)" with Clear, shown only while a sheet filter is on.
class CatalogFilterSummary extends StatelessWidget {
  const CatalogFilterSummary({
    required this.filter,
    required this.onClear,
    super.key,
  });

  final CatalogFilter filter;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (filter.activeCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Filters (${filter.activeCount})',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear')),
        ],
      ),
    );
  }
}
