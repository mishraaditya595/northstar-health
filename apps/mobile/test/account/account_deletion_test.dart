import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../support/fake_account_auth.dart';

void main() {
  test(
    'fresh OTP is required and user email cannot be supplied by UI',
    () async {
      final api = FakeAuthApi()..sessionId = accountA;
      final bound = FakeBoundAccountStore()..saved = accountA;
      final auth = controller(api, bound);
      addTearDown(auth.dispose);
      addTearDown(api.dispose);
      await auth.restore();

      await auth.requestDeletionCode();
      expect(auth.deletionCodeSent, true);
      expect(api.deletionCodeSentTo, 'owner@example.invalid');
      expect(bound.saved, accountA);
      expect(auth.userId, accountA);

      await auth.confirmAccountDeletion('987654');
      expect(api.deleteRequestedFor, isNull);
      expect(auth.userId, accountA);
      expect(bound.saved, accountA);
      expect(auth.error, contains('Verification failed'));
      auth.cancelDeletion();
      expect(auth.deletionCodeSent, false);
    },
  );

  test(
    'server deletion starts only after local binding is durably cleared',
    () async {
      final hold = Completer<void>();
      final api = FakeAuthApi()
        ..sessionId = accountA
        ..holdDeletion = hold;
      final bound = FakeBoundAccountStore()..saved = accountA;
      final auth = controller(api, bound);
      addTearDown(auth.dispose);
      addTearDown(api.dispose);
      await auth.restore();

      await auth.requestDeletionCode();
      final deletion = auth.confirmAccountDeletion('123456');
      await Future<void>.delayed(Duration.zero);
      expect(auth.userId, isNull);
      expect(auth.cloudBackupReady, false);
      expect(auth.busy, true);
      expect(bound.saved, isNull);
      expect(api.deleteRequestedFor, accountA);
      expect(api.serverDeleted, false);
      hold.complete();
      await deletion;
      expect(api.serverDeleted, true);
      expect(api.signedOut, true);
      expect(auth.notice, contains('Account deleted and local workout data erased'));
      expect(auth.error, isNull);
      expect(auth.userId, isNull);
    },
  );

  test(
    'uncertain network receipt does not unlock owner after app restart',
    () async {
      final api = FakeAuthApi()
        ..sessionId = accountA
        ..failDeletionTransport = true;
      final bound = FakeBoundAccountStore()..saved = accountA;
      final recovery = FakeDeletionRecoveryStore();
      final auth = controller(api, bound, recovery: recovery);
      addTearDown(auth.dispose);
      addTearDown(api.dispose);
      await auth.restore();
      await auth.requestDeletionCode();
      await auth.confirmAccountDeletion('123456');

      expect(api.deleteRequestedFor, accountA);
      expect(auth.userId, isNull);
      expect(bound.saved, isNull);
      expect(recovery.saved, accountA);
      expect(auth.error, contains('could not be confirmed'));
      final reopened = controller(api, bound, recovery: recovery);
      addTearDown(reopened.dispose);
      await reopened.restore();
      expect(reopened.userId, isNull);
      expect(reopened.cloudBackupReady, false);
      expect(reopened.deletionRecoveryPending, true);
      expect(api.serverDeleted, false);
    },
  );

  test(
    'secure binding clear failure never calls the destructive endpoint',
    () async {
      final api = FakeAuthApi()..sessionId = accountA;
      final bound = FakeBoundAccountStore()
        ..saved = accountA
        ..failClear = true;
      final auth = controller(api, bound);
      addTearDown(auth.dispose);
      addTearDown(api.dispose);
      await auth.restore();
      await auth.requestDeletionCode();
      await auth.confirmAccountDeletion('123456');
      expect(bound.saved, accountA);
      expect(auth.userId, accountA);
      expect(api.deleteRequestedFor, isNull);
      expect(auth.error, contains('has not been requested'));
    },
  );

  test('wrong-account fresh OTP cannot delete the original account', () async {
    final api = FakeAuthApi()
      ..sessionId = accountA
      ..deletionVerifiedId = accountB;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await auth.requestDeletionCode();
    await auth.confirmAccountDeletion('123456');
    expect(api.deleteRequestedFor, isNull);
    expect(bound.saved, accountA);
    expect(auth.userId, isNull); // A newly signed-in B must lock A immediately.
    expect(auth.error, contains('account changed'));
  });

  test('account switch after sending deletion code stops deletion', () async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await auth.requestDeletionCode();
    api.emitSession(accountB);
    await auth.confirmAccountDeletion('123456');
    expect(api.deleteRequestedFor, isNull);
    expect(bound.saved, accountA);
    expect(auth.userId, isNull);
  });

  test(
    'expired, anonymous and offline sessions cannot start re-verification',
    () async {
      for (final configure in <void Function(FakeAuthApi)>[
        (api) => api.expired = true,
        (api) => api.anonymous = true,
        (api) => api.offline = true,
      ]) {
        final api = FakeAuthApi()..sessionId = accountA;
        configure(api);
        final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
        await auth.restore();
        await auth.requestDeletionCode();
        expect(auth.deletionCodeSent, false);
        expect(api.deleteRequestedFor, isNull);
        auth.dispose();
        await api.dispose();
      }
    },
  );

  test(
    'server commits deletion but response is lost: no account recreated',
    () async {
      final api = FakeAuthApi()
        ..sessionId = accountA
        ..commitThenLoseReceipt = true;
      final bound = FakeBoundAccountStore()..saved = accountA;
      final recovery = FakeDeletionRecoveryStore();
      final auth = controller(api, bound, recovery: recovery);
      addTearDown(auth.dispose);
      addTearDown(api.dispose);
      await auth.restore();
      await auth.requestDeletionCode();
      await auth.confirmAccountDeletion('123456');
      expect(api.serverDeleted, true);
      expect(auth.userId, isNull);
      expect(bound.saved, isNull);
      expect(recovery.saved, accountA);
      expect(auth.error, contains('could not be confirmed'));
      final restarted = controller(api, bound, recovery: recovery);
      addTearDown(restarted.dispose);
      await restarted.restore();
      expect(restarted.deletionRecoveryPending, true);
      await restarted.requestCode('original@example.invalid');
      expect(api.recoveryCodeSentTo, isNull);
      expect(api.sentTo, isNull); // Creating accounts is forbidden in recovery.
      expect(restarted.error, contains('Could not send'));
      expect(bound.saved, isNull);
    },
  );

  test('pending recovery only unlocks the exact original Auth UUID', () async {
    final api = FakeAuthApi()
      ..sessionId = accountA
      ..failDeletionTransport = true;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final recovery = FakeDeletionRecoveryStore();
    final auth = controller(api, bound, recovery: recovery);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await auth.requestDeletionCode();
    await auth.confirmAccountDeletion('123456');
    final restarted = controller(api, bound, recovery: recovery);
    addTearDown(restarted.dispose);
    await restarted.restore();

    api.verifiedId = accountB;
    await restarted.requestCode('wrong@example.invalid');
    expect(api.recoveryCodeSentTo, 'wrong@example.invalid');
    expect(api.sentTo, isNull);
    await restarted.verifyCode('123456');
    expect(restarted.userId, isNull);
    expect(bound.saved, isNull);
    expect(recovery.saved, accountA);
    expect(restarted.error, contains('original account'));

    api.verifiedId = accountA;
    await restarted.requestCode('original@example.invalid');
    await restarted.verifyCode('123456');
    expect(restarted.userId, accountA);
    expect(bound.saved, accountA);
    expect(recovery.saved, isNull);
    expect(restarted.deletionRecoveryPending, false);
  });

  test('failed recovery marker write prevents destructive request', () async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final recovery = FakeDeletionRecoveryStore()..failWrite = true;
    final auth = controller(api, bound, recovery: recovery);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await auth.requestDeletionCode();
    await auth.confirmAccountDeletion('123456');
    expect(api.deleteRequestedFor, isNull);
    expect(auth.userId, isNull);
    expect(bound.saved, isNull);
    expect(auth.error, contains('has not been requested'));
  });

  test('pending guard overrides even a matching account binding', () async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final recovery = FakeDeletionRecoveryStore()..saved = accountA;
    final auth = controller(api, bound, recovery: recovery);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    expect(auth.userId, isNull);
    expect(auth.cloudBackupReady, false);
    expect(auth.deletionRecoveryPending, true);
  });

  test('leaving recovery clears residual binding before guard', () async {
    final api = FakeAuthApi()..sessionId = accountA;
    // Simulate a crash between binding-write and pending-guard cleanup.
    final bound = FakeBoundAccountStore()..saved = accountA;
    final recovery = FakeDeletionRecoveryStore()..saved = accountA;
    final auth = controller(api, bound, recovery: recovery);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await auth.leaveDeletionRecovery();
    expect(auth.userId, isNull);
    expect(bound.saved, isNull);
    expect(recovery.saved, isNull);
    expect(auth.deletionRecoveryPending, false);
    expect(api.signedOut, true);
  });

  test('confirmed deletion clears pending recovery marker', () async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final recovery = FakeDeletionRecoveryStore();
    final auth = controller(api, bound, recovery: recovery);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await auth.requestDeletionCode();
    await auth.confirmAccountDeletion('123456');
    expect(api.serverDeleted, true);
    expect(recovery.saved, isNull);
    expect(auth.deletionRecoveryPending, false);
  });


  test('confirmed deletion removes only the original owner files', () async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final recovery = FakeDeletionRecoveryStore();
    final cleanup = FakeConfirmedDeletionCleanupStore();
    final cleaner = FakeLocalAccountDataCleaner();
    final auth = controller(
      api, bound, recovery: recovery, cleanup: cleanup, cleaner: cleaner,
    );
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await auth.requestDeletionCode();
    await auth.confirmAccountDeletion('123456');
    expect(api.serverDeleted, true);
    expect(cleaner.erased, [accountA]);
    expect(cleaner.lastWaitForUnmount, true);
    expect(cleanup.saved, isNull);
    expect(recovery.saved, isNull);
    expect(bound.saved, isNull);
    expect(auth.userId, isNull);
    expect(auth.error, isNull);
  });

  test('confirmed cleanup failure persists for next launch and retries', () async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final cleanup = FakeConfirmedDeletionCleanupStore();
    final cleaner = FakeLocalAccountDataCleaner()..failErase = true;
    final auth = controller(api, bound, cleanup: cleanup, cleaner: cleaner);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await auth.requestDeletionCode();
    await auth.confirmAccountDeletion('123456');
    expect(api.serverDeleted, true);
    expect(cleaner.erased, isEmpty);
    expect(cleanup.saved, accountA);
    expect(auth.confirmedLocalCleanupPending, true);
    expect(auth.error, contains('not complete'));

    final afterRestart = controller(api, bound, cleanup: cleanup, cleaner: cleaner);
    addTearDown(afterRestart.dispose);
    await afterRestart.restore();
    expect(afterRestart.userId, isNull);
    expect(afterRestart.confirmedLocalCleanupPending, true);
    cleaner.failErase = false;
    await afterRestart.retryConfirmedLocalCleanup();
    expect(cleaner.erased, [accountA]);
    expect(cleanup.saved, isNull);
    expect(afterRestart.confirmedLocalCleanupPending, false);
  });

  test('uncertain server result never authorizes local file erasure', () async {
    final api = FakeAuthApi()
      ..sessionId = accountA
      ..commitThenLoseReceipt = true;
    final cleaner = FakeLocalAccountDataCleaner();
    final cleanup = FakeConfirmedDeletionCleanupStore();
    final auth = controller(
      api, FakeBoundAccountStore()..saved = accountA,
      cleaner: cleaner, cleanup: cleanup,
    );
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await auth.requestDeletionCode();
    await auth.confirmAccountDeletion('123456');
    expect(api.serverDeleted, true);
    expect(cleaner.erased, isEmpty);
    expect(cleanup.saved, isNull);
    expect(auth.confirmedLocalCleanupPending, false);
    expect(auth.deletionRecoveryPending, true);
  });

  test('explicit 400/401/403 server refusal restores the verified owner', () async {
    for (final status in [400, 401, 403]) {
      final api = FakeAuthApi()
        ..sessionId = accountA
        ..deleteRefusalStatus = status;
      final bound = FakeBoundAccountStore()..saved = accountA;
      final recovery = FakeDeletionRecoveryStore();
      final cleaner = FakeLocalAccountDataCleaner();
      final auth = controller(api, bound, recovery: recovery, cleaner: cleaner);
      await auth.restore();
      await auth.requestDeletionCode();
      await auth.confirmAccountDeletion('123456');
      expect(auth.userId, accountA, reason: 'HTTP $status');
      expect(bound.saved, accountA);
      expect(recovery.saved, isNull);
      expect(api.serverDeleted, false);
      expect(cleaner.erased, isEmpty);
      expect(auth.error, contains('Deletion was refused'));
      auth.dispose();
      await api.dispose();
    }
  });

  test('expired session after code delivery resets challenge with message', () async {
    final api = FakeAuthApi()..sessionId = accountA;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await auth.requestDeletionCode();
    expect(auth.deletionCodeSent, true);
    api.expired = true;
    await auth.confirmAccountDeletion('123456');
    expect(auth.deletionCodeSent, false);
    expect(auth.error, contains('session expired'));
    expect(api.deleteRequestedFor, isNull);
  });

  test('email OTP rate limit gives wait guidance instead of connectivity advice', () async {
    final api = FakeAuthApi()
      ..sessionId = accountA
      ..rateLimited = true;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await auth.requestDeletionCode();
    expect(auth.deletionCodeSent, false);
    expect(auth.error, contains('Too many email codes'));
    expect(auth.error, isNot(contains('connection')));
  });

  test('missing verified Auth email prevents deletion code delivery', () async {
    final api = FakeAuthApi()
      ..sessionId = accountA
      ..emailAvailable = false;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await auth.requestDeletionCode();
    expect(auth.deletionCodeSent, false);
    expect(auth.error, contains('verified email'));
  });
}
