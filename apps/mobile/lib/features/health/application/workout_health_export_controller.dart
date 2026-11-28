import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_auth_provider.dart';
import '../../watch/application/watch_status_provider.dart';
import '../../watch/domain/watch_status.dart';
import '../data/health_export_repository.dart';
import '../data/health_reader.dart';
import '../data/health_workout_writer.dart';
import '../data/workout_health_exporter.dart';
import 'health_summary_controller.dart';

/// What the Health tab shows for "Save workouts to Apple Health".
sealed class HealthExportStatus {
  const HealthExportStatus();
}

/// Signed out or no health store here: the row is hidden.
final class HealthExportUnavailable extends HealthExportStatus {
  const HealthExportUnavailable();
}

final class HealthExportOff extends HealthExportStatus {
  const HealthExportOff();
}

final class HealthExportOn extends HealthExportStatus {
  const HealthExportOn({
    required this.saved,
    required this.waiting,
    required this.needsAccess,
  });

  final int saved;
  final int waiting;
  final bool needsAccess;
}

class HealthExportController extends AsyncNotifier<HealthExportStatus> {
  WorkoutHealthExporter? _exporter;
  String? _owner;

  @override
  Future<HealthExportStatus> build() async {
    final owner = ref.watch(healthOwnerIdProvider);
    // The exporter serializes passes, so a rebuild (switch off and on, store
    // change) keeps it while the account is the same: one pass at a time.
    if (owner != _owner) _exporter = null;
    _owner = owner;
    if (owner == null) return const HealthExportUnavailable();
    final writer = ref.watch(healthWorkoutWriterProvider);
    final repository = ref.watch(healthExportRepositoryProvider);
    if (!await writer.isAvailable()) return const HealthExportUnavailable();
    if (!repository.isEnabled(owner)) return const HealthExportOff();
    final exporter = _exporterFor(owner);
    return _on(exporter.summary());
  }

  WorkoutHealthExporter _exporterFor(String owner) =>
      _exporter ??= ref.read(workoutHealthExporterFactoryProvider)(
        accountId: owner,
        stillCurrent: () =>
            ref.mounted &&
            ref.read(accountAuthControllerProvider)?.userId == owner,
        watchPaired: () => switch (ref.read(watchStatusProvider)) {
          WatchHidden() || WatchNotInstalled() => false,
          _ => true,
        },
        clock: ref.read(healthClockProvider),
      );

  HealthExportOn _on(ExportPassResult r) => HealthExportOn(
    saved: r.saved,
    waiting: r.waiting,
    needsAccess: r.blocked,
  );

  /// Enables saving, shows the platform permission prompt once and saves the
  /// workouts. A denied prompt keeps the switch on and shows "Allow access".
  Future<void> turnOn() async {
    final owner = ref.read(healthOwnerIdProvider);
    if (owner == null) return;
    final writer = ref.read(healthWorkoutWriterProvider);
    ref
        .read(healthExportRepositoryProvider)
        .enable(owner, ref.read(healthClockProvider)());
    await writer.requestAccess();
    if (!ref.mounted) return;
    ref.invalidateSelf();
    await future;
    await runPass();
  }

  Future<void> turnOff() async {
    final owner = ref.read(healthOwnerIdProvider);
    if (owner == null) return;
    ref.read(healthExportRepositoryProvider).disable(owner);
    state = const AsyncData(HealthExportOff());
  }

  /// Runs one export pass and refreshes the status. Never throws.
  Future<void> runPass() async {
    try {
      await future;
      final owner = _owner;
      if (!ref.mounted || owner == null) return;
      if (state.requireValue is! HealthExportOn) return;
      final exporter = _exporterFor(owner);
      final result = await exporter.runPass();
      if (!ref.mounted || ref.read(healthOwnerIdProvider) != owner) return;
      if (!ref.read(healthExportRepositoryProvider).isEnabled(owner)) return;
      state = AsyncData(_on(result));
    } catch (_) {
      // The next trigger retries; receipts hold the durable state.
    }
  }

  Future<void> openSettings() async {
    try {
      await ref.read(healthReaderProvider).openSettings();
    } catch (_) {}
  }
}

final healthExportControllerProvider =
    AsyncNotifierProvider<HealthExportController, HealthExportStatus>(
      HealthExportController.new,
    );

final healthExportKickProvider = Provider<void Function()>(
  (ref) =>
      () => unawaited(
        ref.read(healthExportControllerProvider.notifier).runPass(),
      ),
);
