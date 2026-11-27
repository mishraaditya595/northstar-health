import 'package:flutter/material.dart';

import '../../../core/design/dialogs.dart';

/// Three steps to put BeyondRep on a paired watch that does not have it.
Future<void> showWatchInstallSteps(BuildContext context) => showNsSheet<void>(
  context,
  heightFactor: 0.6,
  builder: (sheetContext) => const _InstallSteps(),
);

const _steps = [
  'Open the Watch app on this iPhone.',
  'Scroll down to Available Apps.',
  'Tap Install next to BeyondRep.',
];

class _InstallSteps extends StatelessWidget {
  const _InstallSteps();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          'Install BeyondRep on your watch',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_steps[i], style: theme.textTheme.bodyMedium),
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
