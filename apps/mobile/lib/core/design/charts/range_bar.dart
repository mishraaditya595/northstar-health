import 'package:flutter/material.dart';

/// A track with the "usual" band and an optional marker for today's value.
/// Decorative: the caption beside it carries the meaning.
class NsRangeBar extends StatelessWidget {
  const NsRangeBar({
    required this.low,
    required this.high,
    required this.min,
    required this.max,
    this.value,
    super.key,
  });

  final double low;
  final double high;
  final double? value;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final span = max - min;
    double frac(double v) => span <= 0 ? 0 : ((v - min) / span).clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: SizedBox(
        height: 14,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final bandLeft = frac(low) * w;
            final bandRight = frac(high) * w;
            final markerLeft = value == null
                ? 0.0
                : (frac(value!) * w - 2).clamp(0.0, w - 4);
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 4,
                  height: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  left: bandLeft,
                  width: (bandRight - bandLeft).clamp(4.0, w),
                  top: 4,
                  height: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                if (value != null)
                  Positioned(
                    key: const Key('ns-range-marker'),
                    left: markerLeft,
                    width: 4,
                    top: 0,
                    height: 14,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
