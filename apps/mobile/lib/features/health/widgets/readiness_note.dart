import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clock.dart';
import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/charts/score_ring.dart';
import '../../../core/design/dialogs.dart';
import '../application/health_overview.dart';
import '../application/health_summary_controller.dart';
import '../domain/readiness.dart';
import 'readiness_card.dart';

const _lowTitle = 'Recovery is low today';
const _advice =
    'Consider dropping a set per exercise or keeping effort around RPE 7.';
const _plansUnchanged = 'Your plans are not changed';

/// In-memory flag: the owner and local day the low-readiness note was last
/// shown before a workout start. Never persisted.
class ReadinessStartNoteShown
    extends Notifier<({String owner, DateTime day})?> {
  @override
  ({String owner, DateTime day})? build() => null;

  void mark(String owner, DateTime day) => state = (owner: owner, day: day);
}

final readinessStartNoteShownProvider =
    NotifierProvider<ReadinessStartNoteShown, ({String owner, DateTime day})?>(
      ReadinessStartNoteShown.new,
    );

/// Returns true at once unless today's readiness is Low and the note has not
/// been shown today for this owner. Uses only the current overview value and
/// never waits for a health read. A dismissed note counts as "Not now".
Future<bool> confirmReadinessBeforeStart(
  BuildContext context,
  WidgetRef ref,
) async {
  final owner = ref.read(healthOwnerIdProvider);
  final overview = ref.read(healthOverviewProvider).value;
  final readiness = overview == null
      ? null
      : todaysReadiness(overview, ref.read(localNowProvider))?.result;
  if (owner == null ||
      readiness is! ReadinessReady ||
      readiness.readiness.band != ReadinessBand.low) {
    return true;
  }
  final now = ref.read(localNowProvider);
  final day = DateTime(now.year, now.month, now.day);
  if (ref.read(readinessStartNoteShownProvider) == (owner: owner, day: day)) {
    return true;
  }
  ref.read(readinessStartNoteShownProvider.notifier).mark(owner, day);
  return showNsConfirm(
    context,
    title: _lowTitle,
    message: '$_advice\n\n$_plansUnchanged',
    confirmLabel: 'Start workout',
    cancelLabel: 'Not now',
  );
}

/// Readiness on Train: a card when recovery is low, a one-line row otherwise.
/// Renders nothing while loading, on error, when health is not connected or
/// without a score; health never blocks or changes Train.
class ReadinessNote extends ConsumerWidget {
  const ReadinessNote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(healthOverviewProvider).value;
    if (overview == null) return const SizedBox.shrink();
    final readiness = todaysReadiness(overview, ref.watch(localNowProvider));
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
    final dark = theme.brightness == Brightness.dark;
    final accent = dark
        ? BeyondRepPalette.amberDark
        : BeyondRepPalette.amberLight;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Card(
        margin: EdgeInsets.zero,
        color: dark
            ? BeyondRepPalette.amberSoftDark
            : BeyondRepPalette.amberSoftLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: accent.withValues(alpha: .4)),
        ),
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
                    color: accent,
                    caption: 'Readiness',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _lowTitle,
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
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _seeWhy(context),
                    child: const Text('See why'),
                  ),
                  Text(
                    _plansUnchanged,
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
