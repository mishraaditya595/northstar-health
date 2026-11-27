import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/ids/uuid_factory.dart';
import '../../account/account_auth_provider.dart';
import '../../health/application/health_overview.dart';
import '../../programs/application/program_providers.dart';
import '../../progress/workout_history_state.dart';
import '../../sync/workout_restore_feed.dart';
import '../../sync/workout_upload_coordinator.dart';
import '../../workouts/data/objectbox_workout_outbox.dart';
import '../../workouts/domain/workout_models.dart';
import '../data/objectbox_watch_workout_importer.dart';
import '../data/watch_link.dart';
import '../domain/watch_account_key.dart';
import '../domain/watch_message.dart';
import 'live_watch_workout.dart';
import 'watch_snapshots.dart';
import 'watch_sync_controller.dart';

/// Receives `completed_workout` messages from the watch. Order: the message
/// is for the signed-in account, the payload validates, the importer commits
/// workout, receipt and outbox entry in one transaction, and only then does
/// the watch get its `ack`. Nothing is sent when the message is ignored, so
/// the watch keeps the workout.
class WatchWorkoutInbox {
  WatchWorkoutInbox({
    required this.link,
    required this.importer,
    required this.signedInUserId,
    required this.ids,
    required this.clock,
    required this.onStored,
    this.onImported,
  });

  final WatchLink link;
  final ObjectBoxWatchWorkoutImporter Function(String accountId) importer;
  final String? Function() signedInUserId;
  final UuidFactory ids;
  final DateTime Function() clock;
  final void Function() onStored;

  /// Called with the start time of a workout the phone now holds (stored or
  /// already stored), so a live card of the same workout can go.
  final void Function(DateTime startedAt)? onImported;

  /// Null when the message was ignored (signed out, another account, or the
  /// account changed while importing): nothing was acknowledged.
  Future<WatchImportResult?> handle(CompletedWorkout message) async {
    final user = signedInUserId();
    if (user == null) return null;
    final key = watchAccountKey(user);
    if (message.accountKey != key) return null;

    WatchImportResult result;
    final RemoteWorkoutSnapshot snapshot;
    try {
      snapshot = WorkoutRestorePage.parseWorkout(
        message.workout,
        workoutId: (message.workout['workout_id']! as String).toLowerCase(),
        origins: {WorkoutOrigin.watch},
      );
    } on FormatException {
      return _ack(message, key, WatchImportResult.invalid);
    }
    try {
      result = importer(user).importCompleted(
        messageId: message.messageId,
        snapshot: snapshot,
        platformWorkoutUuid: message.healthkitWorkoutUuid,
        programDay: message.programDay,
      );
    } on StateError catch (e) {
      if (e.message == 'account_changed') return null;
      rethrow;
    }
    if (result == WatchImportResult.stored) onStored();
    if (result != WatchImportResult.invalid) {
      final started = DateTime.tryParse(
        message.workout['started_at_utc'] as String? ?? '',
      );
      if (started != null) onImported?.call(started.toUtc());
    }
    return _ack(message, key, result);
  }

  Future<WatchImportResult> _ack(
    CompletedWorkout message,
    String key,
    WatchImportResult result,
  ) async {
    final ack = buildAck(
      accountKey: key,
      ackedMessageId: message.messageId,
      result: switch (result) {
        WatchImportResult.stored => 'stored',
        WatchImportResult.duplicate => 'duplicate',
        WatchImportResult.invalid => 'rejected',
      },
      reason: result == WatchImportResult.invalid ? 'invalid' : null,
      messageId: ids.newId(),
      nowUtc: clock().toUtc(),
    );
    await link.transfer(jsonEncode(ack.toJson()));
    return result;
  }
}

final watchWorkoutInboxProvider = Provider<WatchWorkoutInbox>((ref) {
  final auth = ref.read(accountAuthControllerProvider);
  final factory = ref.read(watchWorkoutImporterProvider);
  return WatchWorkoutInbox(
    link: ref.read(watchLinkProvider),
    importer: (accountId) => factory(accountId, () => auth?.userId),
    signedInUserId: () => auth?.userId,
    ids: ref.read(watchMessageIdsProvider),
    clock: ref.read(wallClockProvider),
    onStored: () {
      ref.invalidate(completedWorkoutHistoryProvider);
      ref.invalidate(programWeekProvider);
      ref.invalidate(blockedWorkoutCountProvider);
      ref.invalidate(workoutSyncFlagsProvider);
      ref.invalidate(ownPlatformWorkoutIdsProvider);
      ref.read(workoutUploadKickProvider)?.call();
    },
    onImported: (startedAt) => ref
        .read(liveWatchWorkoutProvider.notifier)
        .dropImported(startedAt: startedAt),
  );
});
