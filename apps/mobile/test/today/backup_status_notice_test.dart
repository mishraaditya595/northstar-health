import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/design/page_header.dart';
import 'package:northstar_health/features/today/backup_status_notice.dart';

import '../support/fake_account_auth.dart';

void main() {
  testWidgets('uses InsightCard and responds to offline refresh errors', (
    tester,
  ) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    await auth.restore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BackupStatusNotice(controller: auth)),
      ),
    );
    expect(find.byType(InsightCard), findsNothing);
    api.emitRefreshError();
    await tester.pump();
    expect(find.byType(InsightCard), findsOneWidget);
    expect(find.textContaining('backup paused'), findsOneWidget);
    api.emitSession(accountA);
    await tester.pump();
    expect(find.byType(InsightCard), findsNothing);
  });

  testWidgets('blocked uploads show an accurate local-only warning', (
    tester,
  ) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    await auth.restore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupStatusNotice(controller: auth, blockedCount: 2),
        ),
      ),
    );
    expect(find.byType(InsightCard), findsOneWidget);
    expect(
      find.textContaining('2 completed workouts saved locally'),
      findsOneWidget,
    );
    expect(find.textContaining('No upload will be attempted'), findsOneWidget);
  });

  testWidgets('unsynced workouts offer Sync now', (tester) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    await auth.restore();
    var syncs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupStatusNotice(
            controller: auth,
            unsyncedCount: 1,
            onSyncNow: () => syncs++,
          ),
        ),
      ),
    );
    expect(
      find.textContaining('1 completed workout not synced yet'),
      findsOneWidget,
    );
    await tester.tap(find.text('Sync now'));
    expect(syncs, 1);
    // Sync cannot run while the session is expired; do not offer it.
    api.emitRefreshError();
    await tester.pump();
    expect(find.text('Sync now'), findsNothing);
  });

  testWidgets('standalone previews do not require an account', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BackupStatusNotice(controller: null)),
      ),
    );
    expect(find.byType(InsightCard), findsNothing);
  });
}
