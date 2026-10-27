import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/design/northstar_theme.dart';
import 'package:northstar_health/features/account/account_auth_provider.dart';
import 'package:northstar_health/features/account/account_sync_page.dart';
import 'package:northstar_health/features/account/workout_export_file_writer.dart';
import 'package:northstar_health/features/account/workout_history_export.dart';
import 'package:northstar_health/features/sync/workout_upload_coordinator.dart';

import '../support/fake_account_auth.dart';
import '../support/workout_export_fakes.dart';

class RecordingFileWriter extends WorkoutExportFileWriter {
  RecordingFileWriter() : super(channel: const MethodChannel('test/export'));
  int saves = 0;
  String? lastJson;
  @override
  Future<bool> saveJson(String json) async {
    saves++;
    lastJson = json;
    return true;
  }
}

class HoldingReader implements WorkoutExportReader {
  HoldingReader(this.pause);
  final Completer<void> pause;
  @override
  Future<int> highWatermark() async => 1;
  @override
  Future<List<Map<String, dynamic>>> page({
    required int throughSeq,
    required String? afterId,
    required int limit,
  }) async {
    await pause.future;
    return [exportRow(0)];
  }
}

void main() {
  testWidgets('authenticated export uses OS writer after cloud checks', (
    tester,
  ) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    final writer = RecordingFileWriter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutHistoryExporterProvider.overrideWith(
            (ref) =>
                (owner) => CompletedWorkoutHistoryExporter(
                  accountId: owner,
                  reader: FakeExportReader([exportRow(0)]),
                  authorized: () =>
                      auth.userId == owner && auth.cloudBackupReady,
                ),
          ),
          workoutExportFileWriterProvider.overrideWithValue(writer),
        ],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const AccountSyncPage(),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Export cloud workout history (JSON)'),
      160,
    );
    await tester.ensureVisible(
      find.text('Export cloud workout history (JSON)'),
    );
    await tester.tap(find.text('Export cloud workout history (JSON)'));
    await tester.pumpAndSettle();
    expect(writer.saves, 1);
    expect(writer.lastJson, contains('"workout_count":1'));
    expect(find.text('Workout history exported.'), findsOneWidget);
  });

  testWidgets('expired cloud identity disables export even while local opens', (
    tester,
  ) async {
    final api = FakeAuthApi()
      ..sessionId = accountA
      ..expired = true;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    final writer = RecordingFileWriter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutExportFileWriterProvider.overrideWithValue(writer),
        ],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const AccountSyncPage(),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Export cloud workout history (JSON)'),
      160,
    );
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(
        OutlinedButton,
        'Export cloud workout history (JSON)',
      ),
    );
    expect(button.onPressed, isNull);
    expect(writer.saves, 0);
  });

  testWidgets('sync is disabled while a cloud export is running', (tester) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    final hold = Completer<void>();
    var kicks = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutUploadKickProvider.overrideWithValue(() => kicks++),
          workoutHistoryExporterProvider.overrideWith(
            (ref) => (owner) => CompletedWorkoutHistoryExporter(
              accountId: owner,
              reader: HoldingReader(hold),
              authorized: () => auth.userId == owner && auth.cloudBackupReady,
            ),
          ),
          workoutExportFileWriterProvider.overrideWithValue(RecordingFileWriter()),
        ],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const AccountSyncPage(),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Export cloud workout history (JSON)'), 160,
    );
    await tester.ensureVisible(find.text('Export cloud workout history (JSON)'));
    await tester.tap(find.text('Export cloud workout history (JSON)'));
    await tester.pump();
    expect(find.text('Preparing export…'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Sync now'), -160);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Sync now')).onPressed,
      isNull,
    );
    expect(kicks, 0);
    hold.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('oversize export has permanent error guidance and never saves', (tester) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    final writer = RecordingFileWriter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutHistoryExporterProvider.overrideWith(
            (ref) => (owner) => CompletedWorkoutHistoryExporter(
              accountId: owner,
              reader: FakeExportReader([exportRow(0), exportRow(1), exportRow(2)]),
              maxExportBytes: 1024,
              authorized: () => auth.userId == owner && auth.cloudBackupReady,
            ),
          ),
          workoutExportFileWriterProvider.overrideWithValue(writer),
        ],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const AccountSyncPage(),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Export cloud workout history (JSON)'), 160);
    await tester.ensureVisible(find.text('Export cloud workout history (JSON)'));
    await tester.tap(find.text('Export cloud workout history (JSON)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('too large for safe export'), findsOneWidget);
    expect(writer.saves, 0);
  });

  testWidgets('account changes mid-fetch never open the document picker', (
    tester,
  ) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    final hold = Completer<void>();
    final writer = RecordingFileWriter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutHistoryExporterProvider.overrideWith(
            (ref) =>
                (owner) => CompletedWorkoutHistoryExporter(
                  accountId: owner,
                  reader: HoldingReader(hold),
                  authorized: () =>
                      auth.userId == owner && auth.cloudBackupReady,
                ),
          ),
          workoutExportFileWriterProvider.overrideWithValue(writer),
        ],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const AccountSyncPage(),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Export cloud workout history (JSON)'),
      160,
    );
    await tester.ensureVisible(
      find.text('Export cloud workout history (JSON)'),
    );
    await tester.tap(find.text('Export cloud workout history (JSON)'));
    await tester.pump();
    expect(find.text('Preparing export…'), findsOneWidget);
    api.emitSession(accountB);
    hold.complete();
    await tester.pumpAndSettle();
    expect(writer.saves, 0);
    expect(auth.userId, isNull);
  });
}
