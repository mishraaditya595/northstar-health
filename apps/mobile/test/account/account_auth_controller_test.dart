import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/account/account_auth_controller.dart';
import 'package:northstar_health/features/account/account_gate.dart';

const accountA = '00000000-0000-4000-8000-0000000000a1';
const accountB = '00000000-0000-4000-8000-0000000000b2';

class FakeBoundAccountStore implements BoundAccountStore {
  String? saved;
  bool failClear = false;

  @override
  Future<String?> read() async => saved;

  @override
  Future<void> write(String userId) async => saved = userId;

  @override
  Future<void> clear() async {
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

  @override
  String? get signedInUserId => sessionId;

  @override
  bool get isAnonymous => anonymous;

  @override
  Future<void> sendEmailCode(String email) async => sentTo = email;

  @override
  Future<String> verifyEmailCode(String email, String code) async {
    if (code != '123456') throw StateError('Invalid code');
    sessionId = verifiedId;
    return verifiedId;
  }

  @override
  Future<void> signOutLocally() async {
    signedOut = true;
    sessionId = null;
  }
}

AccountAuthController controller(
  FakeAuthApi api,
  FakeBoundAccountStore bound,
) => AccountAuthController(api, bound);

void main() {
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
    final api = FakeAuthApi()..sessionId = null;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);

    await auth.restore();
    expect(auth.userId, accountA);
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
    expect(
      () => AccountAuthController.validUserId('../other-account'),
      throwsFormatException,
    );
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
