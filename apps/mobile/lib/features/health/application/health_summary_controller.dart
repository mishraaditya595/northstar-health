import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_auth_provider.dart';
import '../data/health_connection_repository.dart';
import '../data/health_reader.dart';

sealed class HealthSummaryState {
  const HealthSummaryState();
}

final class HealthNotConnected extends HealthSummaryState {
  const HealthNotConnected({
    required this.availability,
    required this.platform,
  });

  final HealthAvailability availability;
  final HealthPlatformKind platform;
}

final class HealthConnected extends HealthSummaryState {
  const HealthConnected({
    required this.readings,
    required this.readAt,
    required this.platform,
  });

  final Map<HealthMetric, HealthReading> readings;
  final DateTime readAt;
  final HealthPlatformKind platform;
}

final healthOwnerIdProvider = Provider<String?>(
  (ref) => ref.watch(accountAuthControllerProvider)?.userId,
);

final healthClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class HealthSummaryController extends AsyncNotifier<HealthSummaryState> {
  @override
  Future<HealthSummaryState> build() async {
    final reader = ref.watch(healthReaderProvider);
    final owner = ref.watch(healthOwnerIdProvider);
    final repository = ref.watch(healthConnectionRepositoryProvider);
    if (owner == null || !repository.isConnected(owner)) {
      return HealthNotConnected(
        availability: await reader.availability(),
        platform: reader.platform,
      );
    }
    final now = ref.read(healthClockProvider)();
    final results = await Future.wait(
      HealthMetric.values.map((metric) => _safeRead(reader, metric, now)),
    );
    return HealthConnected(
      readings: {
        for (var i = 0; i < HealthMetric.values.length; i++)
          HealthMetric.values[i]: results[i],
      },
      readAt: now,
      platform: reader.platform,
    );
  }

  Future<HealthReading> _safeRead(
    HealthReader reader,
    HealthMetric metric,
    DateTime now,
  ) async {
    try {
      return await reader.read(metric, now);
    } catch (_) {
      return const HealthReadFailed();
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> connect() async {
    final owner = ref.read(healthOwnerIdProvider);
    if (owner == null) return;
    final reader = ref.read(healthReaderProvider);
    final availability = await reader.availability();
    if (availability == HealthAvailability.needsInstall) {
      await reader.openInstall();
      return;
    }
    if (availability != HealthAvailability.available) return;
    await reader.requestAccess();
    ref
        .read(healthConnectionRepositoryProvider)
        .connect(owner, ref.read(healthClockProvider)());
    ref.invalidateSelf();
    await future;
  }

  Future<void> disconnect() async {
    final owner = ref.read(healthOwnerIdProvider);
    if (owner == null) return;
    ref.read(healthConnectionRepositoryProvider).disconnect(owner);
    ref.invalidateSelf();
    await future;
  }
}

final healthSummaryProvider =
    AsyncNotifierProvider<HealthSummaryController, HealthSummaryState>(
      HealthSummaryController.new,
    );
