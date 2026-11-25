import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/charts/score_ring.dart';
import '../application/health_overview.dart';
import '../domain/readiness.dart';
import 'readiness_card.dart';

const _advice =
    'Consider dropping a set per exercise or keeping effort around RPE 7.';

/// Readiness on Train: a card when recovery is low, a one-line row otherwise.
/// Renders nothing while loading, on error, when health is not connected or
/// without a score; health never blocks or changes Train.
class ReadinessNote extends ConsumerWidget {
  const ReadinessNote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(healthOverviewProvider).value;
    if (overview == null) return const SizedBox.shrink();
    final readiness = switch (overview.readiness) {
      SectionData(:final value) => value,
      SectionGap() => null,
    };
    if (readiness == null) return const SizedBox.shrink();
    return switch (readiness.result) {
      ReadinessReady(readiness: final r) when r.band == ReadinessBand.low =>
        _LowCard(
          score: r.value,
          reasons: readinessReasons(overview, readiness, r),
        ),
      ReadinessReady(readiness: final r) => _Row(
        text: r.band == ReadinessBand.good
            ? 'Readiness ${r.value} · Good to train as planned'
            : 'Readiness ${r.value} · Train as planned, watch effort',
      ),
      ReadinessNotReady() => const SizedBox.shrink(),
    };
  }
}

void _seeWhy(BuildContext context) => context.push('/health/readiness');

class _Row extends StatelessWidget {
  const _Row({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            Expanded(child: Text(text)),
            TextButton(
              onPressed: () => _seeWhy(context),
              child: const Text('See why'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LowCard extends StatelessWidget {
  const _LowCard({required this.score, required this.reasons});

  final int score;
  final String reasons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  NsScoreRing(
                    value: score,
                    size: 48,
                    color: BeyondRepPalette.amberDark,
                    caption: 'Readiness',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recovery is low today',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (reasons.isNotEmpty)
                          Text(
                            reasons,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.mutedColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(_advice),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _seeWhy(context),
                    child: const Text('See why'),
                  ),
                  const Spacer(),
                  Text(
                    'Your plans are not changed',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.mutedColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
