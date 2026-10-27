import 'dart:async';

import 'package:northstar_health/features/account/account_auth_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const accountA = '00000000-0000-4000-8000-0000000000a1';
const accountB = '00000000-0000-4000-8000-0000000000b2';

class FakeBoundAccountStore implements BoundAccountStore {
  String? saved;
  bool failClear = false;
  bool failWrite = false;
  Completer<void>? holdClear;

  @override
  Future<String?> read() async => saved;

  @override
  Future<void> write(String userId) async {
    if (failWrite) throw StateError('Keychain unavailable');
    saved = userId;
  }

  @override
  Future<void> clear() async {
    if (holdClear != null) await holdClear!.future;
    if (failClear) throw StateError('Keychain unavailable');
    saved = null;
  }
}

class FakeAuthApi implements AccountAuthApi {
  String? sessionId;
  bool anonymous = false;
  String verifiedId = accountA;
  String? sentTo;
  bool signedOut = false;
  bool offline = false;
  bool expired = false;
  int? sessionExpiresAtSeconds;
  final _events = StreamController<String?>.broadcast(sync: true);

  @override
  String? get cloudSessionUserId =>
      sessionId != null &&
          !anonymous &&
          !expired &&
          (sessionExpiresAtSeconds == null ||
              sessionExpiresAtSeconds! >
                  DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000)
      ? sessionId
      : null;

  @override
  int? get cloudSessionExpiresAtSeconds => sessionExpiresAtSeconds;

  @override
  Stream<String?> get cloudIdentityChanges => _events.stream;

  void emitSession(String? id, {bool isExpired = false}) {
    sessionId = id;
    expired = isExpired;
    _events.add(cloudSessionUserId);
  }

  void emitRefreshError() => _events.addError(StateError('offline refresh'));

  Future<void> dispose() => _events.close();

  @override
  String? get signedInUserId => sessionId;

  @override
  bool get isAnonymous => anonymous;

  @override
  Future<void> sendEmailCode(String email) async => sentTo = email;

  @override
  Future<String> verifyEmailCode(String email, String code) async {
    if (code != '123456') throw StateError('Invalid code');
    emitSession(verifiedId);
    return verifiedId;
  }

  @override
  Future<void> signOutLocally() async {
    signedOut = true;
    emitSession(null);
    // Mirrors gotrue: local session is gone before the network revoke fails.
    if (offline) throw AuthRetryableFetchException();
  }
}

AccountAuthController controller(
  FakeAuthApi api,
  FakeBoundAccountStore bound,
) => AccountAuthController(api, bound);
