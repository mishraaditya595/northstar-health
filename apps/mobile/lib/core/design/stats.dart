import 'package:flutter/material.dart';

import 'northstar_theme.dart';

/// Direction of a [StatTile] trend; colours come from the theme, not the call.
enum NsTrend { up, down, flat }

/// Headline number card ("Volume 12,400 kg ↗ 8% This week").
class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    this.unit,
    this.trend,
    this.trendLabel,
    this.caption,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final String? unit;
  final NsTrend? trend;
  final String? trendLabel;
  final String? caption;

  /// Shows a chevron and makes the tile tappable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.mutedColor;
    final trendColor = switch (trend) {
      NsTrend.up => const Color(0xFF3F9D5E),
      NsTrend.down => const Color(0xFFC0563A),
      _ => muted,
    };
    final trendIcon = switch (trend) {
      NsTrend.up => Icons.trending_up,
      NsTrend.down => Icons.trending_down,
      _ => Icons.trending_flat,
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (onTap != null) Icon(Icons.chevron_right, color: muted),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 6,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: value),
                        if (unit != null)
                          TextSpan(
                            text: ' $unit',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  if (trend != null && trendLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(trendIcon, size: 16, color: trendColor),
                          const SizedBox(width: 3),
                          Text(
                            trendLabel!,
                            style: TextStyle(
                              color: trendColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (caption != null) ...[
                const SizedBox(height: 6),
                Text(
                  caption!,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Month grid (Sunday first) with trained days filled and today ringed.
class NsMonthCalendar extends StatelessWidget {
  const NsMonthCalendar({
    required this.month,
    required this.highlighted,
    this.today,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  /// Any date in the month to show.
  final DateTime month;

  /// Day numbers (1-31) to fill.
  final Set<int> highlighted;

  /// Local calendar day to ring; ignored when outside [month].
  final DateTime? today;

  /// Null disables the matching arrow.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.mutedColor;
    final first = DateTime.utc(month.year, month.month);
    final days = DateTime.utc(month.year, month.month + 1, 0).day;
    final lead = first.weekday % 7; // Sunday = 0
    final ringed =
        today != null &&
            today!.year == month.year &&
            today!.month == month.month
        ? today!.day
        : null;
    final cells = lead + days;
    final rows = (cells / 7).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_monthNames[month.month - 1]} ${month.year}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Previous month',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final letter in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    letter,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < rows; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _cell(
                      context,
                      row * 7 + col - lead + 1,
                      days,
                      ringed,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(BuildContext context, int day, int days, int? ringed) {
    if (day < 1 || day > days) return const SizedBox(height: 40);
    final scheme = Theme.of(context).colorScheme;
    final trained = highlighted.contains(day);
    final isToday = day == ringed;
    final label =
        '$day ${_monthNames[month.month - 1]}'
        '${trained ? ', trained' : ''}${isToday ? ', today' : ''}';
    return Semantics(
      container: true, // stay a separate node inside a Card
      label: label,
      excludeSemantics: true,
      child: Center(
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: trained
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: .06),
            border: isToday
                ? Border.all(color: scheme.primary, width: 2)
                : null,
          ),
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: trained ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
