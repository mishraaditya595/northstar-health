import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/design/dialogs.dart';
import '../application/health_overview.dart';
import '../application/health_summary_controller.dart';
import '../domain/readiness.dart';

const _lowTitle = 'Energy is low right now';
const _advice =
    'Consider dropping a set per exercise or keeping effort around RPE 7.';
const _plansUnchanged = 'Your plans are not changed';

/// In-memory flag: the owner and local day the low-energy note was last
/// shown before a workout start. Never persisted.
class ReadinessStartNoteShown
    extends Notifier<({String owner, DateTime day})?> {
  @override
  ({String owner, DateTime day})? build() => null;

  void mark(String owner, DateTime day) => state = (owner: owner, day: day);
}

final readinessStartNoteShownProvider =
    NotifierProvider<ReadinessStartNoteShown, ({String owner, DateTime day})?>(
      ReadinessStartNoteShown.new,
    );

/// Returns true at once unless energy now is Low and the note has not
/// been shown today for this owner. Uses only the current overview value and
/// never waits for a health read. A dismissed note counts as "Not now".
Future<bool> confirmReadinessBeforeStart(
  BuildContext context,
  WidgetRef ref,
) async {
  final owner = ref.read(healthOwnerIdProvider);
  final overview = ref.read(healthOverviewProvider).value;
  final energy = overview == null
      ? null
      : currentEnergyScore(overview, ref.read(localNowProvider));
  if (owner == null || energy == null || energy.band != ReadinessBand.low) {
    return true;
  }
  final now = ref.read(localNowProvider);
  final day = DateTime(now.year, now.month, now.day);
  if (ref.read(readinessStartNoteShownProvider) == (owner: owner, day: day)) {
    return true;
  }
  ref.read(readinessStartNoteShownProvider.notifier).mark(owner, day);
  return showNsConfirm(
    context,
    title: _lowTitle,
    message: '$_advice\n\n$_plansUnchanged',
    confirmLabel: 'Start workout',
    cancelLabel: 'Not now',
  );
}
