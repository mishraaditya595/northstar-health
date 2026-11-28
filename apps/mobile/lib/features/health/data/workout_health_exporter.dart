import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/objectbox_store_provider.dart';
import '../../../objectbox.g.dart';
import '../../watch/data/watch_workout_receipt_entity.dart';
import '../../workouts/data/workout_entities.dart';
import '../domain/health_export_state.dart';
import '../domain/outside_workouts.dart';
import '../domain/workout_health_export.dart';
import 'health_export_entities.dart';
import 'health_export_repository.dart';
import 'health_workout_writer.dart';

class ExportPassResult {
  const ExportPassResult({
    required this.saved,
    required this.waiting,
    required this.blocked,
  });

  static const none = ExportPassResult(saved: 0, waiting: 0, blocked: false);

  /// Wanted workouts with a confirmed copy.
  final int saved;

  /// Wanted workouts without one yet (skipped and superseded excluded).
  final int waiting;

  /// Some receipt is blocked on missing write access.
  final bool blocked;
}

const _ownAppId = 'in.beyondrep.app';

/// Runs one serialized export pass: compares this account's completed phone
/// workouts with the receipts and does the missing writes and deletes against
/// the health store, committing a receipt before and after each platform call
/// (ADR-0014). Lives in `data/` because it reads ObjectBox.
class WorkoutHealthExporter {
  WorkoutHealthExporter({
    required this.store,
    required this.accountId,
    required this.repository,
    required this.writer,
    required this.stillCurrent,
    required this.watchPaired,
    required this.clock,
  });

  final Store store;
  final String accountId;
  final HealthExportRepository repository;
  final HealthWorkoutWriter writer;

  /// False once the signed-in account is no longer [accountId].
  final bool Function() stillCurrent;
  final bool Function() watchPaired;
  final DateTime Function() clock;

  Future<ExportPassResult>? _running;
  bool _rerun = false;

  /// A second call while a pass runs schedules one more pass and returns the
  /// running future, which completes after that rerun.
  Future<ExportPassResult> runPass() {
    final running = _running;
    if (running != null) {
      _rerun = true;
      return running;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<ExportPassResult> _loop() async {
    var result = await _pass();
    while (_rerun) {
      _rerun = false;
      if (!stillCurrent()) break;
      result = await _pass();
    }
    return result;
  }

  /// True while this pass may still call the platform: the account is still
  /// signed in and the switch is still on.
  bool _go() => stillCurrent() && repository.isEnabled(accountId);

  /// Counts from the stored workouts and receipts; no platform call.
  ExportPassResult summary() => _summary(_candidates(), _watchLinked());

  DateTime _utc(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  HealthExportReceiptEntity _receipt(
    String uuid,
    HealthExportState state, {
    HealthExportReceiptEntity? prior,
    int? exportedVersion,
    String? platformRecordId,
    int? attempts,
    bool attempted = false,
  }) => HealthExportReceiptEntity(
    workoutUuid: uuid,
    platform: writer.platform,
    state: state.wire,
    exportedVersion: exportedVersion ?? prior?.exportedVersion ?? 0,
    platformRecordId: platformRecordId ?? prior?.platformRecordId,
    attempts: attempts ?? prior?.attempts ?? 0,
    lastAttemptAtMs: attempted
        ? clock().millisecondsSinceEpoch
        : prior?.lastAttemptAtMs ?? 0,
    updatedAtMs: clock().millisecondsSinceEpoch,
  );

  Future<ExportPassResult> _pass() async {
    if (!stillCurrent() || !repository.isEnabled(accountId)) {
      return ExportPassResult.none;
    }
    if (!await writer.isAvailable() || !stillCurrent()) {
      return ExportPassResult.none;
    }

    final candidates = _candidates();
    final linked = _watchLinked();
    final receipts = {
      for (final r in repository.allReceipts()) r.workoutUuid: r,
    };

    final actions = planHealthExport(
      workouts: candidates,
      receipts: {for (final r in receipts.values) r.workoutUuid: _view(r)},
      watchLinkedWorkoutUuids: linked,
      watchPaired: watchPaired(),
      isIos: writer.isIos,
      now: clock(),
    );

    if (actions.isNotEmpty) {
      final hasAccess = await writer.hasWriteAccess();
      if (!stillCurrent()) return _summary(candidates, linked);
      if (!hasAccess) {
        for (final action in actions) {
          final uuid = switch (action) {
            WriteWorkout(:final candidate) => candidate.uuid,
            DeleteOwnCopy(:final workoutUuid) => workoutUuid,
            SupersedeByWatch(:final workoutUuid) => workoutUuid,
            LookupDeletedCopy() => null,
          };
          if (uuid == null) continue;
          repository.putReceipt(
            _receipt(uuid, HealthExportState.blocked, prior: receipts[uuid]),
          );
        }
        return _summary(candidates, linked);
      }
    }

    final byUuid = {for (final c in candidates) c.uuid: c};
    for (final action in actions) {
      if (!_go()) break;
      switch (action) {
        case WriteWorkout():
          await _write(action, receipts[action.candidate.uuid]);
        case DeleteOwnCopy():
          await _delete(
            action,
            receipts[action.workoutUuid],
            byUuid[action.workoutUuid],
          );
        case SupersedeByWatch():
          await _supersede(
            action,
            receipts[action.workoutUuid],
            byUuid[action.workoutUuid],
          );
        case LookupDeletedCopy():
          await _lookupDeleted(action.candidate);
      }
    }
    return _summary(candidates, linked);
  }

  ExportReceiptView _view(HealthExportReceiptEntity r) => ExportReceiptView(
    workoutUuid: r.workoutUuid,
    state:
        HealthExportState.fromWire(r.state) ??
        HealthExportState.failedRetryable,
    exportedVersion: r.exportedVersion,
    platformRecordId: r.platformRecordId,
    attempts: r.attempts,
    lastAttemptAt: _utc(r.lastAttemptAtMs),
  );

  List<ExportCandidate> _candidates() => [
    for (final s in store.box<WorkoutSessionEntity>().getAll())
      if (s.status == 'completed' && s.completedAtMs != null)
        ExportCandidate(
          uuid: s.uuid.toLowerCase(),
          name: s.name,
          origin: s.origin,
          status: s.status,
          startedAt: _utc(s.startedAtMs),
          completedAt: _utc(s.completedAtMs!),
          deleted: s.deletedAtMs != null,
          version: s.updatedAtMs,
          offsetMinutes: s.originalOffsetMinutes,
        ),
  ];

  Set<String> _watchLinked() => {
    for (final r in store.box<WatchWorkoutReceiptEntity>().getAll())
      if (r.platformWorkoutUuid != null && r.platformWorkoutUuid!.isNotEmpty)
        r.workoutUuid.toLowerCase(),
  };

  ExportPassResult _summary(
    List<ExportCandidate> candidates,
    Set<String> linked,
  ) {
    final receipts = {
      for (final r in repository.allReceipts()) r.workoutUuid: r,
    };
    var saved = 0;
    var waiting = 0;
    for (final c in candidates) {
      if (c.origin != 'northstar_phone' ||
          c.deleted ||
          linked.contains(c.uuid)) {
        continue;
      }
      final state = HealthExportState.fromWire(receipts[c.uuid]?.state ?? '');
      switch (state) {
        case HealthExportState.confirmed:
          saved++;
        case HealthExportState.skippedWatch ||
            HealthExportState.supersededByWatch:
          break;
        default:
          waiting++;
      }
    }
    return ExportPassResult(
      saved: saved,
      waiting: waiting,
      blocked: receipts.values.any(
        (r) => r.state == HealthExportState.blocked.wire,
      ),
    );
  }

  Future<void> _write(
    WriteWorkout action,
    HealthExportReceiptEntity? prior,
  ) async {
    final c = action.candidate;
    final end = c.completedAt!;

    // First write of this workout on iOS: look for the watch's entry and for
    // our own copy from an earlier crash or another iPhone on the Apple ID.
    if (writer.isIos && (prior?.exportedVersion ?? 0) == 0) {
      if (!_go()) return;
      final found = await writer.beyondRepWorkoutsIn(
        c.startedAt.subtract(const Duration(minutes: 1)),
        end.add(const Duration(minutes: 1)),
      );
      if (!stillCurrent()) return;
      if (found != null) {
        final watch = found.any(
          (w) =>
              w.sourceId != _ownAppId &&
              overlapsByHalf(c.startedAt, end, w.start, w.end),
        );
        if (watch) {
          repository.putReceipt(
            _receipt(c.uuid, HealthExportState.skippedWatch, prior: prior),
          );
          return;
        }
        for (final w in found) {
          if (w.sourceId == _ownAppId &&
              _sameSecond(w.start, c.startedAt) &&
              _sameSecond(w.end, end)) {
            repository.putReceipt(
              _receipt(
                c.uuid,
                HealthExportState.confirmed,
                prior: prior,
                exportedVersion: c.version,
                platformRecordId: w.platformRecordId,
                attempts: 0,
              ),
            );
            return;
          }
        }
      }
    }

    repository.putReceipt(
      _receipt(
        c.uuid,
        HealthExportState.writing,
        prior: prior,
        attempts: (prior?.attempts ?? 0) + 1,
        attempted: true,
      ),
    );
    if (!_go()) return;
    final result = await writer.write(
      HealthWorkoutRecord(
        workoutUuid: c.uuid,
        name: c.name,
        start: c.startedAt,
        end: end,
        offsetMinutes: c.offsetMinutes,
        version: c.version,
      ),
    );
    if (!stillCurrent()) return;
    final writing = repository.receipt(c.uuid);
    repository.putReceipt(switch (result) {
      HealthWriteOk(:final platformRecordId) => _receipt(
        c.uuid,
        HealthExportState.confirmed,
        prior: writing,
        exportedVersion: c.version,
        platformRecordId: platformRecordId,
        attempts: 0,
      ),
      HealthWriteDenied() => _receipt(
        c.uuid,
        HealthExportState.blocked,
        prior: writing,
      ),
      HealthWriteFailed() || HealthWriteUnavailable() => _receipt(
        c.uuid,
        HealthExportState.failedRetryable,
        prior: writing,
      ),
    });
  }

  bool _sameSecond(DateTime a, DateTime b) =>
      a.millisecondsSinceEpoch ~/ 1000 == b.millisecondsSinceEpoch ~/ 1000;

  /// Own copies of [c] in the store (exact start and end, own source, not the
  /// watch's); null when the read failed.
  Future<List<OwnStoredWorkout>?> _ownCopies(ExportCandidate c) async {
    if (!_go()) return null;
    final end = c.completedAt!;
    final found = await writer.beyondRepWorkoutsIn(
      c.startedAt.subtract(const Duration(minutes: 1)),
      end.add(const Duration(minutes: 1)),
    );
    if (found == null) return null;
    return [
      for (final w in found)
        if (w.sourceId == _ownAppId &&
            _sameSecond(w.start, c.startedAt) &&
            _sameSecond(w.end, end))
          w,
    ];
  }

  /// Removes our copy of [c]. Without a record id on iOS it looks the copy up
  /// first. The plugin returns false for a failed delete and, on iOS, for a
  /// record that is not there: after a false the store is read again and a
  /// missing copy counts as gone. A failed read is a failure.
  Future<HealthWriteResult> _removeCopy(
    ExportCandidate c,
    String? recordId,
  ) async {
    if (writer.isIos && (recordId == null || recordId.isEmpty)) {
      final own = await _ownCopies(c);
      if (own == null) return const HealthWriteFailed();
      for (final w in own) {
        final r = await _deleteOne(c, w.platformRecordId);
        if (r is! HealthWriteOk) return r;
      }
      return const HealthWriteOk('');
    }
    return _deleteOne(c, recordId);
  }

  Future<HealthWriteResult> _deleteOne(
    ExportCandidate c,
    String? recordId,
  ) async {
    if (!_go()) return const HealthWriteFailed();
    final watch = c.origin == 'beyondrep_watch';
    final result = await writer.delete(
      c.uuid,
      recordId,
      start: watch ? c.startedAt : null,
      end: watch ? c.completedAt : null,
    );
    if (result is! HealthWriteFailed || !writer.isIos) return result;
    final own = await _ownCopies(c);
    if (own == null) return result;
    return own.any((w) => w.platformRecordId == recordId)
        ? result
        : const HealthWriteOk('');
  }

  Future<void> _delete(
    DeleteOwnCopy action,
    HealthExportReceiptEntity? prior,
    ExportCandidate? c,
  ) async {
    if (prior == null || c == null) return;
    final retrying = prior.state == HealthExportState.deleting.wire;
    final deleting = _receipt(
      action.workoutUuid,
      HealthExportState.deleting,
      prior: prior,
      attempts: retrying ? prior.attempts : 0,
    );
    repository.putReceipt(deleting);
    final result = await _removeCopy(c, action.platformRecordId);
    if (!stillCurrent()) return;
    repository.putReceipt(switch (result) {
      HealthWriteOk() => _receipt(
        action.workoutUuid,
        HealthExportState.deleted,
        prior: deleting,
      ),
      HealthWriteDenied() => _receipt(
        action.workoutUuid,
        HealthExportState.blocked,
        prior: deleting,
      ),
      // Stays deleting; the planner retries it with the write backoff.
      HealthWriteFailed() || HealthWriteUnavailable() => _receipt(
        action.workoutUuid,
        HealthExportState.deleting,
        prior: deleting,
        attempts: deleting.attempts + 1,
        attempted: true,
      ),
    });
  }

  Future<void> _supersede(
    SupersedeByWatch action,
    HealthExportReceiptEntity? prior,
    ExportCandidate? c,
  ) async {
    if (prior == null || c == null) return;
    final result = await _removeCopy(c, action.platformRecordId);
    if (!stillCurrent()) return;
    if (result is HealthWriteDenied) {
      repository.putReceipt(
        _receipt(action.workoutUuid, HealthExportState.blocked, prior: prior),
      );
      return;
    }
    if (result is! HealthWriteOk) return;
    repository.putReceipt(
      _receipt(
        action.workoutUuid,
        HealthExportState.supersededByWatch,
        prior: prior,
      ),
    );
  }

  Future<void> _lookupDeleted(ExportCandidate c) async {
    final result = await _removeCopy(c, null);
    if (!stillCurrent() || result is! HealthWriteOk) return;
    repository.putReceipt(_receipt(c.uuid, HealthExportState.deleted));
  }
}

typedef WorkoutHealthExporterFactory = WorkoutHealthExporter Function({
  required String accountId,
  required bool Function() stillCurrent,
  required bool Function() watchPaired,
  required DateTime Function() clock,
});

/// Builds an exporter over the signed-in account's store. Tests override it.
final workoutHealthExporterFactoryProvider =
    Provider<WorkoutHealthExporterFactory>((ref) {
      final store = ref.watch(objectBoxStoreProvider);
      final repository = ref.watch(healthExportRepositoryProvider);
      final writer = ref.watch(healthWorkoutWriterProvider);
      return ({
        required accountId,
        required stillCurrent,
        required watchPaired,
        required clock,
      }) => WorkoutHealthExporter(
        store: store,
        accountId: accountId,
        repository: repository,
        writer: writer,
        stillCurrent: stillCurrent,
        watchPaired: watchPaired,
        clock: clock,
      );
    });
