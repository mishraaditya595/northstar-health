import 'package:flutter/material.dart';

import '../../core/date_labels.dart';
import '../../core/design/beyondrep_theme.dart';
import '../../core/design/dialogs.dart';
import '../../core/design/inputs.dart';

/// What the user picked: the weekday of program day 1 (Monday = 1) and, when
/// asked, whether to make the program active.
typedef WeekdayChoice = ({int weekday, bool makeActive});

/// Asks which weekday day 1 falls on. With [askActive], also asks whether the
/// program becomes the active one (on by default).
Future<WeekdayChoice?> showProgramWeekdaySheet(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required int initialWeekday,
  bool askActive = false,
}) {
  return showNsSheet<WeekdayChoice>(
    context,
    heightFactor: 0.7,
    builder: (sheetContext) => _WeekdaySheet(
      title: title,
      confirmLabel: confirmLabel,
      initialWeekday: initialWeekday,
      askActive: askActive,
    ),
  );
}

class _WeekdaySheet extends StatefulWidget {
  const _WeekdaySheet({
    required this.title,
    required this.confirmLabel,
    required this.initialWeekday,
    required this.askActive,
  });

  final String title;
  final String confirmLabel;
  final int initialWeekday;
  final bool askActive;

  @override
  State<_WeekdaySheet> createState() => _WeekdaySheetState();
}

class _WeekdaySheetState extends State<_WeekdaySheet> {
  late int weekday = widget.initialWeekday;
  var makeActive = true;
  var _done = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          widget.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Day 1 of the program falls on this weekday.',
          style: TextStyle(color: theme.mutedColor),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var day = 1; day <= 7; day++)
              NsChip(
                label: weekdayNames[day - 1],
                selected: weekday == day,
                onSelected: (_) => setState(() => weekday = day),
              ),
          ],
        ),
        if (widget.askActive) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              NsCheckButton(
                checked: makeActive,
                onPressed: () => setState(() => makeActive = !makeActive),
                tooltip: 'Make it my active program',
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Make it my active program')),
            ],
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            // A second tap while the sheet closes must not pop again.
            if (_done) return;
            _done = true;
            Navigator.pop<WeekdayChoice>(context, (
              weekday: weekday,
              makeActive: widget.askActive && makeActive,
            ));
          },
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
