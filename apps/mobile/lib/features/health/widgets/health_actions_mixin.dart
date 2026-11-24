import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/health_summary_controller.dart';
import '../data/health_reader.dart';

/// Shared behaviour of the Health tab and the Today row: refresh on app
/// resume and a guard so Connect / Manage / Try again cannot fire twice.
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
      setState(() => _busy = true);
      try {
        await action(ref.read(healthSummaryProvider.notifier));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    };
  }

  /// Tap action for a card: Not allowed -> Manage (connect), Couldn't read ->
  /// Try again (refresh); none for other readings.
  VoidCallback? actionForReading(HealthReading? reading, bool loading) {
    if (reading is HealthNotAllowed) {
      return guarded(loading, (c) => c.connect());
    }
    if (reading is HealthReadFailed) {
      return guarded(loading, (c) => c.refresh());
    }
    return null;
  }
}
