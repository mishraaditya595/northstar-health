import 'package:flutter/material.dart';

import 'beyondrep_theme.dart';

/// Small outlined "i" for explaining a metric; the tap target is 48 x 48 dp.
class NsInfoButton extends StatelessWidget {
  const NsInfoButton({required this.label, required this.onPressed, super.key});

  /// Semantics label, e.g. `About Resting heart rate`.
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).mutedColor;
    return Semantics(
      container: true, // its own node, even inside a labelled card
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: InkResponse(
        onTap: onPressed,
        radius: 24,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: muted, width: 1.5),
              ),
              child: Text(
                'i',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
