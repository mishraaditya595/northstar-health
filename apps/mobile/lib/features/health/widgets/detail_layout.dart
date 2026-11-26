import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/inputs.dart';
import '../../../core/design/layout.dart';
import '../../../core/design/page_header.dart';
import '../application/health_overview.dart';
import '../application/health_summary_controller.dart';
import '../data/health_reader.dart';
import 'health_card_frame.dart';
import 'metric_unavailable.dart';

/// Shell of a health detail screen: back button, [chips], then [builder] with
/// the signed-in account's overview, or its loading, error or connect-first
/// state. Read fresh and held in memory only.
class HealthDetailScaffold extends ConsumerWidget {
  const HealthDetailScaffold({
    required this.title,
    required this.icon,
    required this.chips,
    required this.builder,
    super.key,
  });

  final String title;
  final IconData icon;
  final Widget chips;
  final Widget Function(HealthOverview overview) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(healthOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        // Opened with go (a link) there is nothing to pop: go to Health.
        leading: NsBackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/health'),
        ),
        title: Text(title),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [chips, const SizedBox(height: 16), _content(ref, async)],
      ),
    );
  }

  Widget _content(WidgetRef ref, AsyncValue<HealthOverview?> async) {
    final overview = async.value;
    if (overview != null) return builder(overview);
    if (async.hasError) {
      return InsightCard(
        icon: icon,
        text: const TextSpan(text: "Couldn't read health data."),
        actionLabel: 'Try again',
        onAction: () => ref.read(healthOverviewProvider.notifier).refresh(),
      );
    }
    if (async.isLoading) return const DetailLoading();
    return const HealthCaption('Connect health on the Health tab first.');
  }
}

/// The panels of a detail screen: one column on a phone; on a wide window the
/// first panel (the chart) takes the main column and the rest sit beside it.
/// [DetailPanel] already spaces itself 12 dp below.
class DetailPanels extends StatelessWidget {
  const DetailPanels({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!isWideWindow(context) || children.length < 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return NsSplitColumns(main: [children.first], side: children.sublist(1));
  }
}

/// The Heart, Activity and Body ranges, in days.
const detailRanges = [(7, '7 days'), (30, '30 days')];

/// One chip per range; [selected] is highlighted.
class DetailRangeChips<T> extends StatelessWidget {
  const DetailRangeChips({
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in options)
          NsChip(
            label: label,
            selected: selected == value,
            onSelected: (_) => onSelected(value),
          ),
      ],
    );
  }
}

/// [MetricUnavailable] on a detail screen. As on the overview cards, tapping
/// Not allowed opens Manage and Couldn't read runs [onRetry].
class DetailUnavailable extends ConsumerWidget {
  const DetailUnavailable({
    required this.gap,
    required this.metricName,
    required this.platform,
    required this.onRetry,
    super.key,
  });

  final MetricGap gap;
  final String metricName;
  final HealthPlatformKind platform;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VoidCallback? onTap = switch (gap) {
      MetricGap.notAllowed =>
        () => ref.read(healthSummaryProvider.notifier).manage(),
      MetricGap.failed => onRetry,
      _ => null,
    };
    final unavailable = MetricUnavailable(
      gap: gap,
      metricName: metricName,
      platform: platform,
      onAction: () =>
          ref.read(healthOverviewProvider.notifier).requestMoreAccess(),
    );
    if (onTap == null) return unavailable;
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: unavailable),
    );
  }
}

/// A metric's [DetailPanel] when its read failed, was declined or never
/// requested.
class DetailGapPanel extends StatelessWidget {
  const DetailGapPanel({
    required this.title,
    required this.gap,
    required this.metricName,
    required this.platform,
    required this.onRetry,
    this.trailing,
    super.key,
  });

  final String title;
  final String? trailing;
  final MetricGap gap;
  final String metricName;
  final HealthPlatformKind platform;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => DetailPanel(
    title: title,
    trailing: trailing,
    children: [
      DetailUnavailable(
        gap: gap,
        metricName: metricName,
        platform: platform,
        onRetry: onRetry,
      ),
    ],
  );
}

/// Big value, unit and optional trend on one wrapping line.
class DetailHeadline extends StatelessWidget {
  const DetailHeadline(this.value, {this.unit, this.trend, super.key});

  final String? value;
  final String? unit;
  final Widget? trend;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      runSpacing: 2,
      children: [
        HealthValue(value, unit: unit),
        if (trend != null)
          Padding(padding: const EdgeInsets.only(bottom: 4), child: trend),
      ],
    );
  }
}

/// A [DetailStat]-sized tile whose value could not be read: its [label]
/// over a [DetailUnavailable].
class DetailUnavailableTile extends StatelessWidget {
  const DetailUnavailableTile({
    required this.label,
    required this.gap,
    required this.metricName,
    required this.platform,
    required this.onRetry,
    super.key,
  });

  final String label;
  final MetricGap gap;
  final String metricName;
  final HealthPlatformKind platform;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.mutedColor),
        ),
        DetailUnavailable(
          gap: gap,
          metricName: metricName,
          platform: platform,
          onRetry: onRetry,
        ),
      ],
    );
  }
}

class DetailLoading extends StatelessWidget {
  const DetailLoading({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: CircularProgressIndicator(),
    ),
  );
}

/// A detail card: optional heading, then [children].
class DetailPanel extends StatelessWidget {
  const DetailPanel({
    required this.children,
    this.title,
    this.trailing,
    this.info,
    super.key,
  });

  final String? title;
  final String? trailing;

  /// Explain button right of [title].
  final Widget? info;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        // Charts and rows stay separate nodes for screen readers.
        semanticContainer: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            title!,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ?info,
                      ],
                    ),
                    if (trailing != null) HealthCaption(trailing!),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Label on the left, value on the right; wraps under large text.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {this.info, super.key});

  final String label;
  final String value;

  /// Explain button right of [label].
  final Widget? info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: info == null
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: info == null
                ? Text(label, style: theme.textTheme.bodyMedium)
                : Row(
                    children: [
                      Flexible(
                        child: Text(label, style: theme.textTheme.bodyMedium),
                      ),
                      info!,
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small label, bold value, optional caption.
class DetailStat extends StatelessWidget {
  const DetailStat(this.label, this.value, [this.caption, Key? key, this.info])
    : super(key: key);

  final String label;
  final String value;
  final String? caption;

  /// Explain button right of [label].
  final Widget? info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.mutedColor,
                ),
              ),
            ),
            ?info,
          ],
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (caption != null) HealthCaption(caption!),
      ],
    );
  }
}

/// [children] two per row.
class DetailPairs extends StatelessWidget {
  const DetailPairs(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 12),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
