import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_session_guard.dart';
import 'workout_restore_feed.dart';

/// A per-request snapshot; never cache credentials or JWTs in this service.
class RestoreSessionSnapshot {
  const RestoreSessionSnapshot({
    required this.userId,
    required this.anonymous,
    required this.expiresAtSeconds,
  });

  final String? userId;
  final bool anonymous;
  final int? expiresAtSeconds;
}

typedef RestoreSessionReader = RestoreSessionSnapshot Function();
typedef RestoreRpcInvoker = Future<Object?> Function(
  String functionName,
  Map<String, dynamic> params,
);

/// Read-only transport. The result is validated, never automatically
/// imported or interpreted as permission to overwrite an on-device workout.
abstract class WorkoutRestoreTransport {
  Future<WorkoutRestorePage> fetchPage({
    required int afterSeq,
    required String? cursorEpoch,
    int limit = 100,
  });
}

class SupabaseWorkoutRestoreTransport implements WorkoutRestoreTransport {
  SupabaseWorkoutRestoreTransport({
    required this.accountId,
    required this.readSession,
    required this.invokeRpc,
    int Function()? clockSeconds,
  }) : _clockSeconds =
           clockSeconds ??
           (() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000);

  /// Production wiring uses the same session as the RPC SupabaseClient.
  /// Unit tests inject a controlled identity snapshot and a deferred RPC.
  factory SupabaseWorkoutRestoreTransport.fromClient(
    SupabaseClient client,
    String accountId,
  ) => SupabaseWorkoutRestoreTransport(
    accountId: accountId,
    readSession: () {
      final session = client.auth.currentSession;
      return RestoreSessionSnapshot(
        userId: session?.user.id,
        anonymous: session?.user.isAnonymous ?? true,
        expiresAtSeconds: session?.expiresAt,
      );
    },
    invokeRpc: (name, args) => client.rpc(name, params: args),
  );

  final String accountId;
  final RestoreSessionReader readSession;
  final RestoreRpcInvoker invokeRpc;
  final int Function() _clockSeconds;

  bool get _authorized {
    final session = readSession();
    return matchesCloudWorkoutSession(
      sessionUserId: session.userId,
      anonymous: session.anonymous,
      expiresAtSeconds: session.expiresAtSeconds,
      accountId: accountId,
      nowSeconds: _clockSeconds(),
    );
  }

  @override
  Future<WorkoutRestorePage> fetchPage({
    required int afterSeq,
    required String? cursorEpoch,
    int limit = 100,
  }) async {
    WorkoutRestorePage.validateRequest(
      afterSeq: afterSeq,
      limit: limit,
      requestedEpoch: cursorEpoch,
    );
    if (!_authorized) throw const AuthException('Cloud session unavailable');

    final data = await invokeRpc('get_workout_changes', {
      'p_after_seq': afterSeq,
      'p_limit': limit,
      'p_cursor_epoch': cursorEpoch,
    });

    // Sign-out, account switch or an expiring token while HTTP is pending
    // must never release the page. AuthException is retryable after refresh;
    // no local cursor or workout data has been written.
    if (!_authorized) throw const AuthException('Cloud session unavailable');

    return WorkoutRestorePage.decode(
      data,
      afterSeq: afterSeq,
      limit: limit,
      requestedEpoch: cursorEpoch,
    );
  }
}

/// The account-bound foreground coordinator mounts this factory together
/// with the merged atomic importer. It is never mounted for a guest account.
final workoutRestoreTransportProvider =
    Provider<WorkoutRestoreTransport Function(String)>(
      (ref) =>
          (owner) => SupabaseWorkoutRestoreTransport.fromClient(
            Supabase.instance.client,
            owner,
          ),
    );
