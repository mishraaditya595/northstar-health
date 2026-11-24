import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dialogs.dart';
import '../application/health_summary_controller.dart';
import '../data/health_reader.dart';

/// Shared behaviour of the Health tab and the Today row: refresh on app
/// resume or first show, and a guard so Connect / Manage / Try again cannot
/// fire twice.
mixin HealthActionsMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool _busy = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (mounted) ref.invalidate(healthSummaryProvider);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(healthSummaryProvider.future);
      } catch (_) {
        return;
      }
      if (mounted && _isStale()) ref.invalidate(healthSummaryProvider);
    });
  }

  /// A connected reading from another calendar day or over 5 minutes old.
  bool _isStale() {
    final state = ref.read(healthSummaryProvider).value;
    if (state is! HealthConnected) return false;
    final now = ref.read(healthClockProvider)();
    final at = state.readAt;
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return !sameDay || now.difference(at) > const Duration(minutes: 5);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// A tap handler that runs [action], or null while a previous action or a
  /// reload ([loading]) is in flight.
  VoidCallback? guarded(
    bool loading,
    Future<void> Function(HealthSummaryController controller) action,
  ) {
    if (_busy || loading) return null;
    return () async {
      if (_busy) return;
      setState(() => _busy = true);
      try {
        await action(ref.read(healthSummaryProvider.notifier));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    };
  }

  /// Like [guarded] for Connect: tells the user when the platform
  /// permission call failed.
  VoidCallback? guardedConnect(bool loading) {
    if (_busy || loading) return null;
    return guarded(loading, (c) async {
      if (!await c.connect() && mounted) {
        showNsMessage(context, "Couldn't open health permissions. Try again.");
      }
    });
  }

  /// Tap action for a card: Not allowed -> Manage (settings), Couldn't read ->
  /// Try again (refresh); none for other readings.
  VoidCallback? actionForReading(HealthReading? reading, bool loading) {
    if (reading is HealthNotAllowed) {
      return guarded(loading, (c) => c.manage());
    }
    if (reading is HealthReadFailed) {
      return guarded(loading, (c) => c.refresh());
    }
    return null;
  }
}
