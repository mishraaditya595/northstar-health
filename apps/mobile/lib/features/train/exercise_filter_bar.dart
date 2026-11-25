import 'package:flutter/material.dart';

import '../../core/design/inputs.dart';

const exerciseGroups = ['Chest', 'Back', 'Legs', 'Shoulders', 'Arms', 'Core'];

/// Muscle group chips and an equipment select, shared by the exercise
/// library page and the picker sheet. A null value means "All".
class ExerciseFilterBar extends StatelessWidget {
  const ExerciseFilterBar({
    required this.group,
    required this.equipment,
    required this.equipmentChoices,
    required this.onGroup,
    required this.onEquipment,
    super.key,
  });

  final String? group;
  final String? equipment;
  final List<String> equipmentChoices;
  final ValueChanged<String?> onGroup;
  final ValueChanged<String?> onEquipment;

  @override
  Widget build(BuildContext context) {
    final selected = equipmentChoices.contains(equipment) ? equipment! : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              NsChip(
                label: 'All',
                selected: group == null,
                onSelected: (_) => onGroup(null),
              ),
              for (final name in exerciseGroups) ...[
                const SizedBox(width: 8),
                NsChip(
                  label: name,
                  selected: group == name,
                  onSelected: (on) => onGroup(on ? name : null),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        NsDropdown<String>(
          key: ValueKey(selected),
          dense: true,
          label: 'Equipment',
          value: selected,
          options: [
            const NsOption('', 'All equipment'),
            for (final label in equipmentChoices) NsOption(label, label),
          ],
          onChanged: (value) => onEquipment(value.isEmpty ? null : value),
        ),
      ],
    );
  }
}
