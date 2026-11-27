import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clock.dart';
import '../../../core/design/beyondrep_theme.dart';
import '../application/health_overview.dart';
import '../domain/energy.dart';
import '../domain/readiness.dart';
import 'energy_text.dart';
import 'readiness_card.dart';

String _bandName(ReadinessBand band) => switch (band) {
  ReadinessBand.good => 'Good',
  ReadinessBand.fair => 'Fair',
  ReadinessBand.low => 'Low',
};

/// Energy now inside the Train start card: a tappable strip in the band's
/// colours, or one muted line while the baseline builds. Renders nothing
/// while loading, on error, when health is not connected or without a
/// score; health never blocks or changes Train.
class ReadinessStrip extends ConsumerStatefulWidget {
  const ReadinessStrip({super.key});

  @override
  ConsumerState<ReadinessStrip> createState() => _ReadinessStripState();
}

class _ReadinessStripState extends ConsumerState<ReadinessStrip> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // As the Today row: a stale overview (e.g. read yesterday) is re-read
    // when this is shown or the app resumes.
    _lifecycle = AppLifecycleListener(onResume: _refreshIfStale);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshIfStale());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _refreshIfStale() {
    if (!mounted) return;
    ref.read(healthOverviewProvider.notifier).refreshIfStale();
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(healthOverviewProvider).value;
    if (overview == null) return const SizedBox.shrink();
    final now = ref.watch(localNowProvider);
    final today = currentEnergy(overview, now);
    final energy = today?.energy;
    if (energy != null) {
      return _Ready(energy: energy, learning: today!.learning);
    }
    final building = energyBuilding(overview, now);
    if (building == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        energyBuildingText(building.days),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).mutedColor),
      ),
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({required this.energy, required this.learning});

  final Energy energy;
  final EnergyLearning learning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final band = energy.band;
    final color = readinessBandColor(theme, band);
    final words = readinessBandWords(band);
    final learningText = energyLearningText(learning);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Semantics(
        container: true,
        button: true,
        label: [
          'Energy ${energy.value}, $words.',
          ?learningText,
          'See why',
        ].join(' '),
        excludeSemantics: true,
        child: Material(
          color: readinessBandSoftColor(theme, band),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/health/readiness'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  Text(
                    '${energy.value}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_bandName(band)} energy. $words.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (learningText != null)
                          Text(
                            learningText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.mutedColor,
                            ),
                          ),
                        if (band == ReadinessBand.low)
                          Text(
                            'Your plans are not changed',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.mutedColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: theme.mutedColor),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
