import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../sync/cloud_session_guard.dart';
import '../../sync/workout_restore_transport.dart'
    show RestoreRpcInvoker, RestoreSessionReader, RestoreSessionSnapshot;
import '../domain/catalog_models.dart';
import '../domain/catalog_parser.dart';

const _manifestTimeout = Duration(seconds: 10);
const _snapshotTimeout = Duration(seconds: 20);

/// The session is missing, anonymous, expired or belongs to another account.
class CatalogUnauthorized implements Exception {
  const CatalogUnauthorized();

  @override
  String toString() => 'CatalogUnauthorized';
}

/// The requested release is no longer live (rollback race).
class CatalogNotLive implements Exception {
  const CatalogNotLive();

  @override
  String toString() => 'CatalogNotLive';
}

/// [kind] is `timeout`, `network` or `server`. No message or body is kept.
class CatalogNetworkFailure implements Exception {
  const CatalogNetworkFailure(this.kind);

  final String kind;

  @override
  String toString() => 'CatalogNetworkFailure($kind)';
}

abstract interface class CatalogTransport {
  /// `null` means no release is live.
  Future<CatalogManifest?> fetchManifest();

  /// The raw decoded snapshot JSON; verified by the caller.
  Future<Object?> fetchSnapshot(int release);
}

class SupabaseCatalogTransport implements CatalogTransport {
  SupabaseCatalogTransport({
    required this.accountId,
    required this.readSession,
    required this.invokeRpc,
    int Function()? clockSeconds,
  }) : _clockSeconds =
           clockSeconds ??
           (() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000);

  factory SupabaseCatalogTransport.fromClient(
    SupabaseClient client,
    String accountId,
  ) => SupabaseCatalogTransport(
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
  Future<CatalogManifest?> fetchManifest() async => parseCatalogManifest(
    await _call('catalog_manifest', const {}, _manifestTimeout),
  );

  @override
  Future<Object?> fetchSnapshot(int release) =>
      _call('catalog_snapshot', {'p_release': release}, _snapshotTimeout);

  Future<Object?> _call(
    String name,
    Map<String, dynamic> params,
    Duration timeout,
  ) async {
    if (!_authorized) throw const CatalogUnauthorized();
    final Object? data;
    try {
      data = await invokeRpc(name, params).timeout(timeout);
    } on TimeoutException {
      throw const CatalogNetworkFailure('timeout');
    } on PostgrestException catch (error) {
      if (error.code == 'P0002') throw const CatalogNotLive();
      throw const CatalogNetworkFailure('server');
    } on AuthException {
      throw const CatalogUnauthorized();
    } on Exception {
      throw const CatalogNetworkFailure('network');
    }
    // Sign-out or an account switch while HTTP was pending releases nothing.
    if (!_authorized) throw const CatalogUnauthorized();
    return data;
  }
}
