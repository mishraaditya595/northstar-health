import 'dart:async';

import 'package:northstar_health/features/account/account_auth_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const accountA = '00000000-0000-4000-8000-0000000000a1';
const accountB = '00000000-0000-4000-8000-0000000000b2';

class FakeDeletionRecoveryStore implements DeletionRecoveryStore {
  String? saved;
  bool failWrite = false;
  bool failClear = false;

  @override
  Future<String?> read() async => saved;

  @override
  Future<void> write(String originalOwner) async {
    if (failWrite) throw StateError('Secure deletion recovery write failed');
    saved = originalOwner;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('Secure deletion recovery clear failed');
    saved = null;
  }
}

class FakeConfirmedDeletionCleanupStore implements ConfirmedDeletionCleanupStore {
  String? saved;
  bool failWrite = false;
  bool failClear = false;

  @override
  Future<String?> read() async => saved;

  @override
  Future<void> write(String owner) async {
    if (failWrite) throw StateError('Secure cleanup marker unavailable');
    saved = owner;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('Secure cleanup marker clear failed');
    saved = null;
  }
}

class FakeLocalAccountDataCleaner implements LocalAccountDataCleaner {
  final List<String> erased = <String>[];
  bool failErase = false;
  bool lastWaitForUnmount = false;

  @override
  Future<void> erase(String owner, {bool waitForUnmount = false}) async {
    lastWaitForUnmount = waitForUnmount;
    if (failErase) throw StateError('ObjectBox files still locked');
    erased.add(owner);
  }
}

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
  bool failDeletionRequest = false;
  bool failDeletionVerify = false;
  bool failDeletionTransport = false;
  bool serverDeleted = false;
  bool commitThenLoseReceipt = false;
  int? deleteRefusalStatus;
  bool rateLimited = false;
  String? recoveryCodeSentTo;
  String? deleteRequestedFor;
  String? deletionCodeSentTo;
  Completer<void>? holdDeletion;
  bool emailAvailable = true;
  String deletionVerifiedId = accountA;
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
  String? get signedInEmail =>
      sessionId != null && emailAvailable ? 'owner@example.invalid' : null;

  @override
  Future<void> sendRecoveryCode(String email) async {
    if (offline || serverDeleted) throw StateError('Original account deleted');
    recoveryCodeSentTo = email;
  }

  @override
  Future<void> sendDeletionCode(String email) async {
    if (rateLimited) {
      throw const AuthApiException('Rate limit', statusCode: '429');
    }
    if (offline || failDeletionRequest) throw StateError('network');
    deletionCodeSentTo = email;
  }

  @override
  Future<String> verifyDeletionCode(String email, String code) async {
    if (offline || failDeletionVerify || code != '123456') {
      throw StateError('OTP failed');
    }
    emitSession(deletionVerifiedId);
    return deletionVerifiedId;
  }

  @override
  Future<void> deleteAccountOnServer(String accountId) async {
    deleteRequestedFor = accountId;
    if (deleteRefusalStatus != null) {
      throw AccountDeletionRejected(deleteRefusalStatus!);
    }
    if (holdDeletion != null) await holdDeletion!.future;
    if (commitThenLoseReceipt) {
      serverDeleted = true;
      throw StateError('response lost AFTER server commit');
    }
    if (offline || failDeletionTransport) {
      throw StateError('deletion status unknown');
    }
    serverDeleted = true;
  }

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
  FakeBoundAccountStore bound, {
  FakeDeletionRecoveryStore? recovery,
  FakeConfirmedDeletionCleanupStore? cleanup,
  FakeLocalAccountDataCleaner? cleaner,
}) => AccountAuthController(
  api,
  bound,
  recovery ?? FakeDeletionRecoveryStore(),
  cleanupStore: cleanup ?? FakeConfirmedDeletionCleanupStore(),
  localCleaner: cleaner ?? FakeLocalAccountDataCleaner(),
);
