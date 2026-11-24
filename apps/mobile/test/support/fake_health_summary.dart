import 'dart:async';

import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Fixed-state stand-in for [HealthSummaryController] that records calls.
/// Set [connectGate] / [refreshGate] to hold an action in flight.
class FakeHealthSummaryController extends HealthSummaryController {
  FakeHealthSummaryController(this.initial);

  /// `null` keeps `build` pending forever (loading with no previous value).
  final HealthSummaryState? initial;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int refreshCalls = 0;
  int buildCalls = 0;
  Completer<void>? connectGate;
  Completer<void>? refreshGate;

  /// Holds the next `build` (a reload keeps the previous value meanwhile).
  Completer<void>? buildGate;

  @override
  Future<HealthSummaryState> build() async {
    buildCalls++;
    final value = initial;
    if (value == null) return Completer<HealthSummaryState>().future;
    await buildGate?.future;
    return value;
  }

  @override
  Future<void> connect() async {
    connectCalls++;
    await connectGate?.future;
  }

  @override
  Future<void> disconnect() async => disconnectCalls++;

  @override
  Future<void> refresh() async {
    refreshCalls++;
    await refreshGate?.future;
  }
}

Override fakeHealthSummary(FakeHealthSummaryController controller) =>
    healthSummaryProvider.overrideWith(() => controller);
