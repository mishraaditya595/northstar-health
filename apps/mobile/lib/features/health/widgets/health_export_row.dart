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

  String _counts(int saved, int waiting) => saved > 0 && waiting > 0
      ? 'On · $saved saved, $waiting waiting'
      : saved > 0
      ? 'On · $saved saved'
      : waiting > 0
      ? 'On · $waiting waiting'
      : 'On';

  String _subtitle(HealthExportStatus status) => switch (status) {
    HealthExportOn(needsAccess: true) => 'Allow access in Settings',
    HealthExportOn(
      :final saved,
      :final waiting,
      offersWatchHealthAccess: true,
    ) =>
      '${_counts(saved, waiting)} · Allow heart rate and calories for watch '
          'workouts',
    HealthExportOn(:final saved, :final waiting) => _counts(saved, waiting),
    _ => 'Off',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(healthExportControllerProvider).value;
    if (status == null || status is HealthExportUnavailable) {
      return const SizedBox.shrink();
    }
    final name = healthPlatformName(platform);
    final notifier = ref.read(healthExportControllerProvider.notifier);

    Future<void> confirmStop() async {
      final stop = await showNsConfirm(
        context,
        title: 'Stop saving workouts?',
        message:
            'New workouts will no longer be saved to $name. Workouts '
            'already saved stay there.',
        confirmLabel: 'Stop saving',
      );
      if (stop) await notifier.turnOff();
    }

    Future<void> tap() async {
      if (status is HealthExportOn) {
        if (status.needsAccess) {
          final action = await showNsSheet<_AccessAction>(
            context,
            heightFactor: 0.4,
            builder: (_) => _AccessSheet(name: name),
          );
          if (action == _AccessAction.openSettings) {
            await notifier.openSettings();
          } else if (action == _AccessAction.stop) {
            await notifier.turnOff();
          }
          return;
        }
        if (status.offersWatchHealthAccess) {
          final action = await showNsSheet<_AccessAction>(
            context,
            heightFactor: 0.4,
            builder: (_) => const _WatchHealthSheet(),
          );
          if (action == _AccessAction.allowWatchHealth) {
            await notifier.allowWatchHealth();
          } else if (action == _AccessAction.stop) {
            await confirmStop();
          }
          return;
        }
        await confirmStop();
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
      trailing: status is HealthExportOn && status.needsAccess
          ? const NsTag('On', warning: true)
          : null,
      onTap: tap,
    );
  }
}

enum _AccessAction { openSettings, allowWatchHealth, stop }

class _AccessSheet extends StatelessWidget {
  const _AccessSheet({required this.name});

  final String name;

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
            'Allow access in Settings',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "BeyondRep can't save workouts to $name until you allow it in "
          'Settings.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_AccessAction.openSettings),
          child: const Text('Open Settings'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_AccessAction.stop),
          child: Text('Stop saving', style: TextStyle(color: theme.mutedColor)),
        ),
      ],
    );
  }
}

class _WatchHealthSheet extends StatelessWidget {
  const _WatchHealthSheet();

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
            'Watch heart rate and calories',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your watch measures heart rate and calories during a workout. '
          'Allow BeyondRep to save them to Health Connect with the workout. '
          'Without this, watch workouts are not saved to Health Connect.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_AccessAction.allowWatchHealth),
          child: const Text('Allow heart rate and calories'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_AccessAction.stop),
          child: Text('Stop saving', style: TextStyle(color: theme.mutedColor)),
        ),
      ],
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
