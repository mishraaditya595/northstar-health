import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dialogs.dart';
import '../application/health_overview.dart';
import '../application/health_summary_controller.dart';

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
        if (!mounted) return;
        ref.invalidate(healthSummaryProvider);
        onShownOrResumed();
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(healthSummaryProvider.future);
      } catch (_) {
        return;
      }
      if (mounted && _isStale()) ref.invalidate(healthSummaryProvider);
      if (mounted) onShownOrResumed();
    });
  }

  /// Runs after the first show and on every app resume, once the summary
  /// refresh has been decided.
  @protected
  void onShownOrResumed() {}

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
    return _guard(
      loading,
      () => action(ref.read(healthSummaryProvider.notifier)),
    );
  }

  /// Like [guarded] for an overview action (Allow more data, Try again).
  VoidCallback? guardedOverview(
    bool loading,
    Future<void> Function(HealthOverviewController controller) action,
  ) => _guard(loading, () => action(ref.read(healthOverviewProvider.notifier)));

  VoidCallback? _guard(bool loading, Future<void> Function() action) {
    if (_busy || loading) return null;
    return () async {
      if (_busy) return;
      setState(() => _busy = true);
      try {
        await action();
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
}
