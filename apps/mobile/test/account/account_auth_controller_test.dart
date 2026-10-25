import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/storage/account_store.dart';
import 'package:northstar_health/features/account/account_gate.dart';

import '../support/fake_account_auth.dart';

void main() {
  test(
    'expired JWT pauses backup without blocking local workout access',
    () async {
      final api = FakeAuthApi()
        ..sessionId = accountA
        ..expired = true;
      final bound = FakeBoundAccountStore()..saved = accountA;
      final auth = controller(api, bound);
      addTearDown(auth.dispose);
      await auth.restore();
      expect(auth.userId, accountA);
      expect(auth.backupPaused, true);
      api.emitSession(accountA);
      expect(auth.cloudBackupReady, true);
      api.emitSession(null);
      expect(auth.userId, accountA);
      expect(auth.backupPaused, true);
    },
  );

  test('unexpected account change locks old partition immediately', () async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    await auth.restore();
    expect(auth.cloudBackupReady, true);
    api.emitSession(accountB);
    expect(auth.userId, isNull);
    expect(bound.saved, accountA);
    expect(auth.cloudBackupReady, false);
  });

  test('SDK offline refresh stream error pauses backup immediately', () async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    await auth.restore();
    expect(auth.cloudBackupReady, true);
    var notifications = 0;
    auth.addListener(() => notifications++);
    api.emitRefreshError();
    expect(notifications, greaterThan(0));
    expect(auth.userId, accountA);
    expect(auth.backupPaused, true);
    api.emitSession(accountA);
    expect(auth.cloudBackupReady, true);
  });

  test(
    'different expired account locks previously bound owner immediately',
    () async {
      final api = FakeAuthApi()..sessionId = accountA;
      final bound = FakeBoundAccountStore()..saved = accountA;
      final auth = controller(api, bound);
      addTearDown(auth.dispose);
      await auth.restore();
      api.emitSession(accountB, isExpired: true);
      expect(auth.userId, isNull);
      expect(bound.saved, accountA);
    },
  );

  test('fresh install has no access without a verified account', () async {
    final api = FakeAuthApi();
    final binding = FakeBoundAccountStore();
    final auth = controller(api, binding);
    addTearDown(auth.dispose);

    await auth.restore();
    expect(auth.userId, isNull);
    expect(binding.saved, isNull);
    expect(auth.isAuthenticated, false);
  });

  test('OTP unlocks only after durable account binding', () async {
    final api = FakeAuthApi();
    final bound = FakeBoundAccountStore();
    final auth = controller(api, bound);
    addTearDown(auth.dispose);

    await auth.requestCode(' EXAMPLE@TEST.INVALID ');
    expect(api.sentTo, 'example@test.invalid');
    expect(auth.userId, isNull);
    await auth.verifyCode('123456');
    expect(auth.userId, accountA);
    expect(bound.saved, accountA);
  });

  test('returning verified owner can reopen offline', () async {
    // supabase_flutter keeps an expired session when refresh cannot connect.
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);

    await auth.restore();
    expect(auth.userId, accountA);
  });

  test('rejected refresh keeps bound owner local access (ADR-0005)', () async {
    final api = FakeAuthApi()..sessionId = null;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);

    await auth.restore();
    expect(auth.userId, accountA);
  });

  test('corrupt binding locks without throwing or erasing it', () async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = 'not-an-account';
    final auth = controller(api, bound);
    addTearDown(auth.dispose);

    await auth.restore();
    expect(auth.userId, isNull);
    expect(bound.saved, 'not-an-account');
  });

  test('failed binding write stays locked and asks for a new code', () async {
    final api = FakeAuthApi();
    final bound = FakeBoundAccountStore()..failWrite = true;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);

    await auth.requestCode('test@example.invalid');
    await auth.verifyCode('123456');
    expect(auth.userId, isNull);
    expect(auth.codeSent, false);
    expect(auth.error, contains('new code'));
  });

  test('a different active session cannot unlock old owner data', () async {
    final api = FakeAuthApi()..sessionId = accountB;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);

    await auth.restore();
    expect(auth.userId, isNull);
    expect(bound.saved, accountA);
  });

  test('anonymous Supabase auth cannot unlock a bound account', () async {
    final api = FakeAuthApi()
      ..sessionId = accountA
      ..anonymous = true;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);

    await auth.restore();
    expect(auth.userId, isNull);
  });

  test('sign-out locks app and erases secure account binding', () async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    await auth.restore();

    await auth.signOut();
    expect(auth.userId, isNull);
    expect(bound.saved, isNull);
    expect(api.signedOut, true);
  });

  test('offline sign-out still succeeds once the binding is gone', () async {
    final api = FakeAuthApi()
      ..sessionId = accountA
      ..offline = true;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    await auth.restore();

    await auth.signOut();
    expect(auth.userId, isNull);
    expect(bound.saved, isNull);
    expect(auth.error, isNull);
  });

  test('failed keychain clear never claims a successful sign-out', () async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()
      ..saved = accountA
      ..failClear = true;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    await auth.restore();

    await auth.signOut();
    expect(auth.userId, accountA);
    expect(bound.saved, accountA);
    expect(api.signedOut, false);
    expect(auth.error, isNotNull);
  });

  test('two verified owners have different native ObjectBox partitions', () {
    expect(
      accountStoreRelativePath(accountA, projectHost: 'dev.supabase.co'),
      isNot(accountStoreRelativePath(accountB, projectHost: 'dev.supabase.co')),
    );
    expect(
      accountStoreRelativePath(accountA, projectHost: 'dev.supabase.co'),
      'northstar_accounts/dev.supabase.co/$accountA',
    );
  });

  test('different Supabase projects use distinct local partitions', () {
    expect(
      accountStoreRelativePath(accountA, projectHost: 'dev.supabase.co'),
      isNot(
        accountStoreRelativePath(accountA, projectHost: 'prod.supabase.co'),
      ),
    );
  });

  test('untrusted storage directory identifiers are rejected', () {
    expect(() => validAccountId('../other-account'), throwsFormatException);
  });

  testWidgets('no workout routes mounted for locked user', (tester) async {
    final api = FakeAuthApi();
    final bound = FakeBoundAccountStore();
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    await auth.restore();

    var openedCount = 0;
    await tester.pumpWidget(
      AccountGate(
        controller: auth,
        authenticatedBuilder: (id) {
          openedCount++;
          return MaterialApp(home: Text('Workouts: $id'));
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Send sign-in code'), findsOneWidget);
    expect(find.text('Train'), findsNothing);
    expect(openedCount, 0);

    await auth.requestCode('test@example.invalid');
    await auth.verifyCode('123456');
    await tester.pumpAndSettle();
    expect(openedCount, greaterThan(0));
    expect(find.text('Workouts: $accountA'), findsOneWidget);

    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Workouts: $accountA'), findsNothing);
    expect(find.text('Send sign-in code'), findsOneWidget);
  });
}
