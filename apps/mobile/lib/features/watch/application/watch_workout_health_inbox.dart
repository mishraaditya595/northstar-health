import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/ids/uuid_factory.dart';
import '../../account/account_auth_provider.dart';
import '../../health/application/health_overview.dart';
import '../../health/application/own_workout_health.dart';
import '../../health/data/health_export_entities.dart';
import '../../health/data/health_export_repository.dart';
import '../../health/data/health_workout_writer.dart';
import '../../health/data/watch_workout_lookup.dart';
import '../../health/domain/health_export_state.dart';
import '../../health/domain/workout_health_export.dart';
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
/// Ack rules: no ack (the watch keeps the series, up to its 7-day cap, and
/// resends) for a workout the phone does not hold yet, a workout that is not a
/// completed watch workout, a message whose start or end does not match the
/// stored workout, heart rate or calories write access missing while the
/// account's switch is on (it is written once the user allows access), a
/// resend inside the receipt backoff, and any write failure;
/// `rejected`/`wrong_account` for another account; `rejected`/`not_written`
/// when nothing will ever be written (not Android, Health Connect missing or
/// unsupported, switch off, workout deleted); `duplicate` for a workout
/// already exported at its current version; `stored` after a confirmed write.
///
/// Health Connect version: a write uses `workout version * 1000 + attempt`
/// (attempt 1, 2, ... since the last confirmed write, at most 999), so a retry
/// after a failed or partial write is a greater version and Health Connect does
/// not ignore the upsert; the receipt keeps the plain workout version.
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

  static const _timeTolerance = Duration(seconds: 2);

  final WatchLink link;
  final String? Function() signedInUserId;
  final UuidFactory ids;
  final DateTime Function() clock;
  final WatchWorkoutLookup workout;
  final HealthExportRepository repository;
  final HealthWorkoutWriter writer;

  /// Called with the workout UUID after a confirmed write, so history reads
  /// the entry fresh.
  final void Function(String workoutUuid)? onWritten;

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
    // A message about other times is not about this workout.
    if (_differs(message.startUtc, stored.startedAt) ||
        _differs(message.endUtc, stored.completedAt!)) {
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
    if (!await writer.isAvailable()) {
      return _ack(message, key, 'rejected', 'not_written');
    }
    // The switch is on: without write access the watch keeps the series and
    // the write happens once the user allows it.
    if (!await writer.hasWatchHealthWriteAccess()) return null;
    if (signedInUserId() != user) return null;
    if (prior != null &&
        prior.state == HealthExportState.failedRetryable.wire &&
        clock().difference(
              DateTime.fromMillisecondsSinceEpoch(
                prior.lastAttemptAtMs,
                isUtc: true,
              ),
            ) <
            healthExportBackoff(prior.attempts)) {
      return null;
    }
    final attempt = (prior?.attempts ?? 0) + 1;

    repository.putReceipt(
      _receipt(
        uuid,
        HealthExportState.writing,
        prior: prior,
        attempts: attempt,
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
        version: stored.version * 1000 + (attempt > 999 ? 999 : attempt),
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
        onWritten?.call(uuid);
        return _ack(message, key, 'stored', null);
      case HealthWriteDenied():
        // Not a backoff case: the user may allow access any moment.
        repository.putReceipt(
          _receipt(uuid, HealthExportState.blocked, prior: writing),
        );
        return null;
      case HealthWriteFailed() || HealthWriteUnavailable():
        repository.putReceipt(
          _receipt(uuid, HealthExportState.failedRetryable, prior: writing),
        );
        return null;
    }
  }

  bool _differs(String utc, DateTime stored) =>
      DateTime.parse(utc).difference(stored).abs() > _timeTolerance;

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
    onWritten: (uuid) {
      ref.invalidate(ownPlatformWorkoutIdsProvider);
      ref.invalidate(watchWorkoutPlatformIdProvider(uuid));
    },
  );
});
