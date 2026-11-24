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
  const HealthConnected({required this.readAt, required this.platform});

  /// When the connection state was built; the values themselves come from
  /// the overview.
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
    return HealthConnected(
      readAt: ref.read(healthClockProvider)(),
      platform: reader.platform,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Returns false when the platform call failed; state is then unchanged and
  /// no connection is recorded. The error is never rethrown or logged.
  Future<bool> connect() async {
    // Everything the post-await work needs is read first: the account scope
    // can be disposed while the permission sheet is open.
    final owner = ref.read(healthOwnerIdProvider);
    if (owner == null) return true;
    final reader = ref.read(healthReaderProvider);
    final repository = ref.read(healthConnectionRepositoryProvider);
    final connectedAt = ref.read(healthClockProvider)();
    try {
      final availability = await reader.availability();
      if (availability == HealthAvailability.needsInstall) {
        await reader.openInstall();
        return true;
      }
      if (availability != HealthAvailability.available) return true;
      await reader.requestAccess();
    } catch (_) {
      return false;
    }
    // Disposed (sign-out or account switch): the account-bound store may be
    // closed, so record nothing.
    if (!ref.mounted) return true;
    try {
      repository.connect(owner, connectedAt);
      ref.invalidateSelf();
      await future;
    } catch (_) {
      return false;
    }
    return true;
  }

  /// Opens the platform's permission settings (Not allowed · Manage). Never
  /// throws; the resume refresh re-reads after the user returns.
  Future<void> manage() async {
    try {
      await ref.read(healthReaderProvider).openSettings();
    } catch (_) {}
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
