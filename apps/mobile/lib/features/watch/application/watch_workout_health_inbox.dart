import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/ids/uuid_factory.dart';
import '../../account/account_auth_provider.dart';
import '../../health/application/health_overview.dart';
import '../../health/data/health_export_entities.dart';
import '../../health/data/health_export_repository.dart';
import '../../health/data/health_workout_writer.dart';
import '../../health/data/watch_workout_lookup.dart';
import '../../health/domain/health_export_state.dart';
import '../data/watch_link.dart';
import '../domain/watch_account_key.dart';
import '../domain/watch_message.dart';
import 'watch_snapshots.dart';
import 'watch_sync_controller.dart';

/// Receives `workout_health` from a Wear OS watch (stage 3b): the heart rate
/// and total calories of a workout the phone already imported. It writes them
/// to Health Connect through the Phase 5 writer, keeps only the receipt (record
/// id, state, version) and acks. The values live in memory for the write; they
/// never reach ObjectBox, the outbox, Supabase, exports or logs.
///
/// Ack rules: no ack (the watch resends) for a workout the phone does not hold
/// yet, a workout that is not a completed watch workout, and any write failure;
/// `rejected`/`wrong_account` for another account; `rejected`/`not_written`
/// when nothing may be written (not Android, Health Connect missing, switch off,
/// permission missing, workout deleted); `duplicate` for a workout already
/// exported at its current version; `stored` after a confirmed write.
class WatchWorkoutHealthInbox {
  WatchWorkoutHealthInbox({
    required this.link,
    required this.signedInUserId,
    required this.ids,
    required this.clock,
    required this.workout,
    required this.repository,
    required this.writer,
    this.onWritten,
  });

  final WatchLink link;
  final String? Function() signedInUserId;
  final UuidFactory ids;
  final DateTime Function() clock;
  final WatchWorkoutLookup workout;
  final HealthExportRepository repository;
  final HealthWorkoutWriter writer;

  /// Called after a confirmed write, so history reads the entry fresh.
  final void Function()? onWritten;

  Future<void> _queue = Future.value();

  /// The ack that was sent, or null when none was. Calls run one at a time, so
  /// two copies of a message write once.
  Future<Ack?> handle(WorkoutHealth message) {
    final run = _queue.then((_) => _handle(message));
    _queue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<Ack?> _handle(WorkoutHealth message) async {
    final user = signedInUserId();
    if (user == null) return null;
    final key = watchAccountKey(user);
    if (message.accountKey != key) {
      return _ack(message, key, 'rejected', 'wrong_account');
    }
    final uuid = message.workoutId.toLowerCase();
    final stored = workout(uuid);
    if (stored == null ||
        stored.status != 'completed' ||
        stored.completedAt == null ||
        stored.origin != 'beyondrep_watch') {
      return null;
    }
    if (stored.deleted || writer.isIos || !repository.isEnabled(user)) {
      return _ack(message, key, 'rejected', 'not_written');
    }
    final prior = repository.receipt(uuid);
    if (prior != null &&
        prior.state == HealthExportState.confirmed.wire &&
        prior.exportedVersion >= stored.version) {
      return _ack(message, key, 'duplicate', null);
    }
    if (!await writer.isAvailable() ||
        !await writer.hasWatchHealthWriteAccess()) {
      return _ack(message, key, 'rejected', 'not_written');
    }
    if (signedInUserId() != user) return null;

    repository.putReceipt(
      _receipt(
        uuid,
        HealthExportState.writing,
        prior: prior,
        attempts: (prior?.attempts ?? 0) + 1,
        attempted: true,
      ),
    );
    final result = await writer.write(
      HealthWorkoutRecord(
        workoutUuid: uuid,
        name: stored.name,
        start: stored.startedAt,
        end: stored.completedAt!,
        offsetMinutes: stored.offsetMinutes,
        version: stored.version,
        totalKcal: message.totalKcal,
        heartRate: [
          for (final p in message.heartRate)
            HeartRateMinute(at: DateTime.parse(p.atUtc).toUtc(), bpm: p.bpm),
        ],
      ),
    );
    // The account changed while the platform call ran: nothing is confirmed
    // for it and the watch resends.
    if (signedInUserId() != user) return null;
    final writing = repository.receipt(uuid);
    switch (result) {
      case HealthWriteOk(:final platformRecordId):
        repository.putReceipt(
          _receipt(
            uuid,
            HealthExportState.confirmed,
            prior: writing,
            exportedVersion: stored.version,
            platformRecordId: platformRecordId,
            attempts: 0,
          ),
        );
        onWritten?.call();
        return _ack(message, key, 'stored', null);
      case HealthWriteDenied() ||
          HealthWriteFailed() ||
          HealthWriteUnavailable():
        repository.putReceipt(
          _receipt(uuid, HealthExportState.failedRetryable, prior: writing),
        );
        return null;
    }
  }

  HealthExportReceiptEntity _receipt(
    String uuid,
    HealthExportState state, {
    HealthExportReceiptEntity? prior,
    int? exportedVersion,
    String? platformRecordId,
    int? attempts,
    bool attempted = false,
  }) {
    final now = clock().millisecondsSinceEpoch;
    return HealthExportReceiptEntity(
      workoutUuid: uuid,
      platform: writer.platform,
      state: state.wire,
      exportedVersion: exportedVersion ?? prior?.exportedVersion ?? 0,
      platformRecordId: platformRecordId ?? prior?.platformRecordId,
      attempts: attempts ?? prior?.attempts ?? 0,
      lastAttemptAtMs: attempted ? now : prior?.lastAttemptAtMs ?? 0,
      updatedAtMs: now,
    );
  }

  Future<Ack> _ack(
    WorkoutHealth message,
    String key,
    String result,
    String? reason,
  ) async {
    final ack = buildAck(
      accountKey: key,
      ackedMessageId: message.messageId,
      result: result,
      reason: reason,
      messageId: ids.newId(),
      nowUtc: clock().toUtc(),
    );
    await link.transfer(jsonEncode(ack.toJson()));
    return ack;
  }
}

final watchWorkoutHealthInboxProvider = Provider<WatchWorkoutHealthInbox>((
  ref,
) {
  final auth = ref.read(accountAuthControllerProvider);
  return WatchWorkoutHealthInbox(
    link: ref.read(watchLinkProvider),
    signedInUserId: () => auth?.userId,
    ids: ref.read(watchMessageIdsProvider),
    clock: ref.read(wallClockProvider),
    workout: ref.read(watchWorkoutLookupProvider),
    repository: ref.read(healthExportRepositoryProvider),
    writer: ref.read(healthWorkoutWriterProvider),
    onWritten: () => ref.invalidate(ownPlatformWorkoutIdsProvider),
  );
});
