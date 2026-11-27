import 'package:flutter/material.dart';

import 'beyondrep_theme.dart';

/// A quiet one-line status with a leading dot, for a state that needs no
/// action ("Apple Watch · synced 10:43"). With [onTap] the whole row is a
/// 48 dp target; the text wraps at large text sizes.
class NsStatusLine extends StatelessWidget {
  const NsStatusLine(this.text, {this.onTap, super.key});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.mutedColor,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(alignment: AlignmentDirectional.centerStart, child: row),
      ),
    );
  }
}
