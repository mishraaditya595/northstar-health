import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/dialogs.dart';
import '../../../core/design/page_header.dart';
import '../application/workout_health_export_controller.dart';
import '../data/health_reader.dart';
import '../health_format.dart';

/// "Save workouts to Apple Health / Health Connect": the per-account switch
/// (ADR-0014). Hidden while signed out, loading or when the store is
/// unavailable.
class HealthExportRow extends ConsumerWidget {
  const HealthExportRow({required this.platform, super.key});

  final HealthPlatformKind platform;

  String _subtitle(HealthExportStatus status) => switch (status) {
    HealthExportOn(needsAccess: true) => 'Allow access in Settings',
    HealthExportOn(:final saved, :final waiting) =>
      saved > 0 && waiting > 0
          ? 'On · $saved saved, $waiting waiting'
          : saved > 0
          ? 'On · $saved saved'
          : waiting > 0
          ? 'On · $waiting waiting'
          : 'On',
    _ => 'Off',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(healthExportControllerProvider).value;
    if (status == null || status is HealthExportUnavailable) {
      return const SizedBox.shrink();
    }
    final name = healthPlatformName(platform);
    final on = status is HealthExportOn;
    final notifier = ref.read(healthExportControllerProvider.notifier);

    Future<void> tap() async {
      if (status is HealthExportOn) {
        if (status.needsAccess) return notifier.openSettings();
        final stop = await showNsConfirm(
          context,
          title: 'Stop saving workouts?',
          message:
              'New workouts will no longer be saved to $name. Workouts '
              'already saved stay there.',
          confirmLabel: 'Stop saving',
        );
        if (stop) await notifier.turnOff();
        return;
      }
      if (!context.mounted) return;
      final turnOn = await showNsSheet<bool>(
        context,
        heightFactor: 0.6,
        builder: (sheetContext) => _FirstUseSheet(
          name: name,
          appleHealth: platform == HealthPlatformKind.appleHealth,
        ),
      );
      if (turnOn == true) await notifier.turnOn();
    }

    return NsListCard(
      icon: Icons.fitness_center,
      title: 'Save workouts to $name',
      subtitle: _subtitle(status),
      trailing: ExcludeSemantics(
        child: Switch(value: on, onChanged: (_) => tap()),
      ),
      onTap: tap,
    );
  }
}

class _FirstUseSheet extends StatelessWidget {
  const _FirstUseSheet({required this.name, required this.appleHealth});

  final String name;

  /// The Apple Watch sentence only applies on iOS; Android has no watch
  /// writer in this phase.
  final bool appleHealth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Semantics(
          header: true,
          child: Text(
            'Save workouts to $name',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'BeyondRep will save each workout you finish on this phone to $name '
          'as Strength training, with its name, start and end. Your past '
          'workouts here are saved too. Heart rate and calories are not '
          'included.${appleHealth ? ' Apple Watch workouts are already in '
                    'Apple Health and are not saved twice.' : ''}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Turn on'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Not now', style: TextStyle(color: theme.mutedColor)),
        ),
      ],
    );
  }
}
