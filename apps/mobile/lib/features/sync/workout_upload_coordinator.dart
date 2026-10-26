import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../account/account_auth_controller.dart';
import '../account/account_auth_provider.dart';
import '../progress/workout_history_state.dart';
import '../workouts/data/objectbox_workout_outbox.dart';
import 'cloud_session_guard.dart';
import 'objectbox_workout_restore_importer.dart';
import 'workout_restore_feed.dart';
import 'workout_restore_transport.dart';

/// Supabase RPC authorization is decided by the server JWT + RLS. The mobile
/// binary only contains its public publishable key, never privileged tokens.
abstract class WorkoutUploadTransport {
  Future<Map<String, dynamic>> send(
    WorkoutSyncOperation operation, {
    required int expectedServerRevision,
  });
}

class SupabaseWorkoutUploadTransport implements WorkoutUploadTransport {
  SupabaseWorkoutUploadTransport(this.client, this.accountId);

  final SupabaseClient client;
  final String accountId;

  @override
  Future<Map<String, dynamic>> send(
    WorkoutSyncOperation operation, {
    required int expectedServerRevision,
  }) async {
    final session = client.auth.currentSession;
    if (!matchesCloudWorkoutSession(
      sessionUserId: session?.user.id,
      anonymous: session?.user.isAnonymous ?? true,
      expiresAtSeconds: session?.expiresAt,
      accountId: accountId,
      nowSeconds: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
    )) {
      throw const AuthException('Cloud session unavailable');
    }
    // Do not accept a caller-supplied owner ID; the server derives auth.uid().
    final data = await client.rpc(
      'sync_workout',
      params: {
        'p_operation_id': operation.operationUuid,
        'p_workout_id': operation.sessionUuid,
        'p_expected_revision': expectedServerRevision,
        'p_action': operation.action,
        'p_payload': jsonDecode(operation.payloadJson),
      },
    );
    if (data is! Map) {
      throw const FormatException('Unexpected sync response');
    }
    return Map<String, dynamic>.from(data);
  }
}

/// Optional trigger in isolated widget tests; production overrides it.
final workoutUploadKickProvider = Provider<void Function()?>((ref) => null);

/// Testable transport factory; no real Supabase accounts are created in tests.
final workoutUploadTransportProvider =
    Provider<WorkoutUploadTransport Function(String)>(
      (ref) =>
          (owner) =>
              SupabaseWorkoutUploadTransport(Supabase.instance.client, owner),
    );

final workoutUploadCoordinatorProvider = Provider<WorkoutUploadCoordinator>((
  ref,
) {
  final auth = ref.watch(accountAuthControllerProvider);
  final owner = auth?.userId;
  if (auth == null || owner == null) {
    throw StateError('Workout uploads require a bound account');
  }
  final coordinator = WorkoutUploadCoordinator(
    accountId: owner,
    auth: auth,
    outbox: ref.watch(workoutOutboxProvider),
    transport: ref.watch(workoutUploadTransportProvider)(owner),
    restoreTransport: ref.watch(workoutRestoreTransportProvider)(owner),
    restoreImporter: ref.watch(workoutRestoreImporterProvider)(
      owner,
      () => auth.userId,
    ),
    onQueueChanged: () => ref.invalidate(blockedWorkoutCountProvider),
    // Rebuild tagged UI only when a workout's sync state actually changed.
    onSyncStateChanged: () {
      final outbox = ref.read(workoutOutboxProvider);
      if (!mapEquals(outbox.syncFlags(), ref.read(workoutSyncFlagsProvider))) {
        ref.invalidate(workoutSyncFlagsProvider);
      }
    },
    onRestored: () => ref.invalidate(completedWorkoutHistoryProvider),
  );
  ref.onDispose(coordinator.dispose);
  // Never perform ObjectBox writes or RPCs while Riverpod builds a provider.
  scheduleMicrotask(coordinator.start);
  return coordinator;
});

/// Foreground-only serialized upload-then-restore on account entry, refresh,
/// app resume and bounded periodic retry. OS background work is not implied.
class WorkoutUploadCoordinator with WidgetsBindingObserver {
  WorkoutUploadCoordinator({
    required this.accountId,
    required this.auth,
    required this.outbox,
    required this.transport,
    this.restoreTransport,
    this.restoreImporter,
    this.onRestored,
    DateTime Function()? clock,
    this.onQueueChanged,
    this.onSyncStateChanged,
    this.pollInterval = const Duration(seconds: 45),
  }) : assert((restoreTransport == null) == (restoreImporter == null)),
       _clock = clock ?? DateTime.now;

  final String accountId;
  final AccountAuthController auth;
  final ObjectBoxWorkoutOutbox outbox;
  final WorkoutUploadTransport transport;

  /// Both fields must be provided together. Null keeps legacy upload-only
  /// tests and the uploader's non-restore behavior unchanged.
  final WorkoutRestoreTransport? restoreTransport;
  final ObjectBoxWorkoutRestoreImporter? restoreImporter;
  final void Function()? onRestored;
  final void Function()? onQueueChanged;

  /// After each serialized drain, when per-workout sync tags may change.
  final void Function()? onSyncStateChanged;
  final DateTime Function() _clock;
  final Duration pollInterval;

  Timer? _poller;
  bool _running = false;
  bool _disposed = false;
  bool _started = false;
  bool _backfillChecked = false;
  bool _rerunRequested = false;
  bool _foreground = true;

  /// Stable non-sensitive diagnostic category, never a raw exception/payload.
  String? lastFailureKind;

  /// Stable non-sensitive restore diagnostic; the blockedCode itself remains
  /// durable in the owner-specific ObjectBox Store.
  String? lastRestoreFailureKind;

  bool get isUploading => _running;
  bool get isStopped => _disposed;

  bool get _isAuthorized =>
      !_disposed &&
      _foreground &&
      auth.userId == accountId &&
      auth.cloudBackupReady;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    auth.addListener(kick);
    _poller = Timer.periodic(pollInterval, (_) => kick());
    kick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) kick();
  }

  void kick() {
    if (!_isAuthorized) return;
    if (_running) {
      // A newly completed workout or resumed session must not lose its kick
      // just because the previous RPC is awaiting a network response.
      _rerunRequested = true;
      return;
    }
    unawaited(drain());
  }

  /// Serialized, per-account drain. Testing can call this without any timers.
  /// A process/account switch can stop this worker while the RPC is in flight:
  /// check disposal and identity before *every* subsequent ObjectBox write.
  Future<void> drain() async {
    if (!_isAuthorized) return;
    if (_running) {
      _rerunRequested = true;
      return;
    }
    _running = true;
    try {
      do {
        _rerunRequested = false;
        await _drainBatch();
        // Serialize pull with the SAME foreground worker as uploads.
        // No upload RPC can interleave between restore fetch and import.
        if (_isAuthorized) await _pullBatch();
      } while (_rerunRequested && _isAuthorized);
    } finally {
      _running = false;
      // ACKs and restore skips change which workouts show as not synced.
      if (!_disposed) onSyncStateChanged?.call();
    }
  }

  Future<void> _drainBatch() async {
    // One invalid historical record must never prevent uploads of newly
    // completed workouts. We attempt backfill once per bound app session.
    if (!_backfillChecked) {
      try {
        if (outbox.backfillCompleted() > 0) onQueueChanged?.call();
      } catch (_) {
        lastFailureKind = 'backfill_failed';
      } finally {
        _backfillChecked = true;
      }
    }
    try {
      for (var sent = 0; sent < 25 && _isAuthorized; sent++) {
        final reserved = outbox.reserveNext(
          nowMs: _clock().toUtc().millisecondsSinceEpoch,
          onBlocked: onQueueChanged,
        );
        if (reserved == null) break;
        final operation = reserved.operation;
        if (!_isCompletedSnapshot(operation)) {
          if (_isAuthorized) {
            outbox.markBlocked(
              operationUuid: operation.operationUuid,
              localRevision: operation.localRevision,
              code: 'invalid_snapshot',
            );
            onQueueChanged?.call();
            lastFailureKind = 'invalid_local_snapshot';
          }
          continue;
        }
        try {
          final result = await transport
              .send(
                operation,
                expectedServerRevision: reserved.expectedServerRevision,
              )
              .timeout(const Duration(seconds: 20));
          if (!_isAuthorized) break;
          if (result['result'] == 'conflict') {
            outbox.markConflict(
              operationUuid: operation.operationUuid,
              localRevision: operation.localRevision,
            );
            onQueueChanged?.call();
            lastFailureKind = 'revision_conflict';
            continue;
          }
          final revision = result['revision'];
          final cursor = result['change_seq'];
          if (result['result'] != 'applied' ||
              revision is! int ||
              revision != reserved.expectedServerRevision + 1 ||
              cursor is! int ||
              cursor <= 0 ||
              result['processing'] != 'processed' ||
              result['replay'] is! bool) {
            // The server may have applied the operation, but no local
            // acknowledgement is safe without the complete response.
            lastFailureKind = 'invalid_server_ack';
            break;
          }
          final acknowledged = outbox.acknowledge(
            operationUuid: operation.operationUuid,
            localRevision: operation.localRevision,
            serverRevision: revision,
            serverChangeSeq: cursor,
          );
          if (!acknowledged) {
            lastFailureKind = 'ack_persist_failed';
          } else if (lastFailureKind != 'backfill_failed') {
            lastFailureKind = null;
          }
          if (!acknowledged) break;
        } on PostgrestException catch (error) {
          if (!_isAuthorized) break;
          if (error.code == '22023') {
            // Terminal malformed payload; keep a local-only blocked receipt.
            outbox.markBlocked(
              operationUuid: operation.operationUuid,
              localRevision: operation.localRevision,
              code: 'server_validation',
            );
            onQueueChanged?.call();
            lastFailureKind = 'server_validation';
            continue;
          }
          // Auth errors, unavailable network, rate limits and 5xx leave the
          // operation pending. It is retried after persisted backoff.
          lastFailureKind = 'rpc_unavailable';
          break;
        } on AuthException {
          lastFailureKind = 'auth_unavailable';
          break;
        } on FormatException {
          // An uncertain response is never treated as a successful ACK.
          lastFailureKind = 'invalid_rpc_response';
          break;
        } on TimeoutException {
          lastFailureKind = 'rpc_timeout';
          break;
        } catch (_) {
          // Neither a payload nor raw exception is exposed in diagnostics.
          lastFailureKind = 'rpc_unexpected_failure';
          break;
        }
      }
    } catch (_) {
      // Do not expose a raw ObjectBox exception or account data.
      lastFailureKind = 'local_queue_failure';
    }
  }

  /// Bounded foreground-only pull. The importer itself commits snapshots and
  /// the cursor atomically; no cursor is advanced on RPC/validation failures.
  /// This worker never clears a durable blockedCode or skips remote changes.
  Future<void> _pullBatch() async {
    final pull = restoreTransport;
    final importer = restoreImporter;
    if (pull == null || importer == null || !_isAuthorized) return;
    // Pending uploads finish (or back off) before any remote state is read;
    // they clear on their own. Conflicted/blocked uploads never clear here,
    // so they do not defer the feed: the importer skips and records only
    // that workout's remote change and keeps the local copy.
    try {
      if (outbox.pending(limit: 1).isNotEmpty) {
        lastRestoreFailureKind = 'upload_unresolved';
        return;
      }
    } catch (_) {
      lastRestoreFailureKind = 'local_queue_failure';
      return;
    }

    var resetCount = 0;
    const maxPagesPerPass = 4;
    for (var index = 0; index < maxPagesPerPass && _isAuthorized; index++) {
      WorkoutRestoreCursor cursor;
      try {
        cursor = importer.readCursor();
      } on RestoreImportException catch (error) {
        if (_isAuthorized) lastRestoreFailureKind = error.code;
        return;
      } catch (_) {
        if (_isAuthorized) lastRestoreFailureKind = 'restore_store_failure';
        return;
      }
      if (cursor.blockedCode != null) {
        lastRestoreFailureKind = cursor.blockedCode;
        return;
      }
      try {
        final page = await pull
            .fetchPage(
              afterSeq: cursor.nextCursor,
              cursorEpoch: cursor.epoch,
              limit: 100,
            )
            .timeout(const Duration(seconds: 20));
        // A sign-out/dispose/token expiry during the RPC cannot mutate the
        // old owner's ObjectBox Store, even if a test transport ignores auth.
        if (!_isAuthorized) return;
        // A local workout may have entered the outbox while the RPC was in
        // flight. Defer the page; do not import over a transient edit.
        if (outbox.pending(limit: 1).isNotEmpty) {
          lastRestoreFailureKind = 'upload_unresolved';
          return;
        }
        final applied = importer.applyPage(
          page,
          afterSeq: cursor.nextCursor,
          requestedEpoch: cursor.epoch,
        );
        if (!_isAuthorized) return;
        if (applied.imported > 0 || applied.tombstones > 0) onRestored?.call();
        if (page.cursorReset) {
          resetCount++;
          // Server should return at most one reset per pass. If it repeatedly
          // resets a known epoch, do not burn retries or silently clear data.
          if (resetCount > 1) {
            lastRestoreFailureKind = 'repeated_cursor_reset';
            return;
          }
          if (index == maxPagesPerPass - 1) _rerunRequested = true;
          continue; // Persisted zero cursor and new epoch: fetch from zero.
        }
        if (!page.hasMore) {
          lastRestoreFailureKind = null;
          return;
        }
        if (applied.alreadyApplied ||
            applied.cursor.nextCursor <= cursor.nextCursor) {
          lastRestoreFailureKind = 'restore_no_progress';
          return;
        }
        if (index == maxPagesPerPass - 1) _rerunRequested = true;
      } on RestoreContractException catch (error) {
        if (!_isAuthorized) return;
        if (!error.request) {
          try {
            importer.recordBlocked(
              afterSeq: cursor.nextCursor,
              requestedEpoch: cursor.epoch,
              code: error.code,
            );
          } catch (_) {
            lastRestoreFailureKind = 'restore_store_failure';
            return;
          }
        }
        lastRestoreFailureKind = error.code;
        return;
      } on RestoreImportException catch (error) {
        if (_isAuthorized) lastRestoreFailureKind = error.code;
        return;
      } on AuthException {
        if (_isAuthorized) lastRestoreFailureKind = 'restore_auth_unavailable';
        return;
      } on TimeoutException {
        if (_isAuthorized) lastRestoreFailureKind = 'restore_timeout';
        return;
      } on PostgrestException {
        if (_isAuthorized) lastRestoreFailureKind = 'restore_rpc_unavailable';
        return;
      } catch (_) {
        if (_isAuthorized) lastRestoreFailureKind = 'restore_unavailable';
        return;
      }
    }
  }

  static bool _isCompletedSnapshot(WorkoutSyncOperation op) {
    if (op.action != 'upsert') return false;
    try {
      final decoded = jsonDecode(op.payloadJson);
      return decoded is Map<String, dynamic> &&
          decoded['schema_version'] == 1 &&
          decoded['status'] == 'completed' &&
          decoded['origin'] == 'northstar_phone' &&
          decoded['workout_id'] == op.sessionUuid;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _poller?.cancel();
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      auth.removeListener(kick);
    }
  }
}

/// Keep the serialized upload/restore coordinator alive only while authenticated.
/// This widget is never mounted for locked, anonymous or guest sessions.
class AccountWorkoutUploadHost extends ConsumerWidget {
  const AccountWorkoutUploadHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(workoutUploadCoordinatorProvider);
    return child;
  }
}
