import 'dart:async';

import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Fixed-state stand-in for [HealthOverviewController] that records calls.
class FakeHealthOverviewController extends HealthOverviewController {
  FakeHealthOverviewController(this.initial, {this.pending = false});

  final HealthOverview? initial;

  /// Keeps `build` pending forever (loading with no value).
  final bool pending;
  int buildCalls = 0;
  int refreshCalls = 0;
  int refreshIfStaleCalls = 0;
  int requestMoreAccessCalls = 0;

  @override
  Future<HealthOverview?> build() async {
    buildCalls++;
    if (pending) return Completer<HealthOverview?>().future;
    return initial;
  }

  @override
  Future<void> refresh() async => refreshCalls++;

  @override
  Future<void> refreshIfStale() async => refreshIfStaleCalls++;

  @override
  Future<void> requestMoreAccess() async => requestMoreAccessCalls++;
}

Override fakeHealthOverview(FakeHealthOverviewController controller) =>
    healthOverviewProvider.overrideWith(() => controller);
