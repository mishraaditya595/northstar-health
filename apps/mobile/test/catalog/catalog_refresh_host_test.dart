import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/features/account/account_auth_controller.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/catalog/application/catalog_refresh_host.dart';
import 'package:beyondrep/features/catalog/data/catalog_transport.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/catalog/domain/catalog_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_account_auth.dart';
import 'catalog_fixtures.dart';

Future<CatalogSnapshot?> _parse(String text) async {
  try {
    return parseCatalogSnapshot(jsonDecode(text));
  } on Object {
    return null;
  }
}

void main() {
  late Directory dir;
  late FakeAuthApi api;
  late AccountAuthController auth;
  late DateTime now;
  final r1 = snapshotJson();

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('catalog_host_test');
    api = FakeAuthApi()..sessionId = accountA;
    auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    await auth.restore();
    now = DateTime.utc(2026, 11, 26, 12);
  });

  tearDown(() async {
    auth.dispose();
    await api.dispose();
    dir.deleteSync(recursive: true);
  });

  FakeCatalogTransport serving() => FakeCatalogTransport(
    manifest: () async => manifestFor(r1),
    snapshot: (_) async => r1,
  );

  Widget harness(FakeCatalogTransport transport, {Key? key}) => ProviderScope(
    key: key,
    overrides: [
      catalogDirectoryProvider.overrideWithValue(dir),
      catalogTransportProvider.overrideWithValue(transport),
      catalogClockProvider.overrideWithValue(() => now),
      catalogParserProvider.overrideWithValue(_parse),
      accountAuthControllerProvider.overrideWithValue(auth),
    ],
    child: MaterialApp(
      home: CatalogRefreshHost(
        child: Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(catalogStateProvider);
            return Text(
              'release ${state.snapshot?.release} ${state.status.name}',
            );
          },
        ),
      ),
    ),
  );

  // Real file IO does not progress inside the fake-async test zone: let it
  // run, then flush the microtasks that resume the awaiting code, repeatedly.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }
  }

  testWidgets('refreshes once on start', (tester) async {
    final t = serving();
    await tester.pumpWidget(harness(t));
    await settle(tester);

    expect(t.manifestCalls, 1);
    expect(find.text('release 1 ready'), findsOneWidget);
  });

  testWidgets('refreshes again on resume after 24 hours', (tester) async {
    final t = serving();
    await tester.pumpWidget(harness(t));
    await settle(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(t.manifestCalls, 1, reason: 'still fresh');

    now = now.add(const Duration(hours: 25));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(t.manifestCalls, 2);
  });

  testWidgets('does not refresh while signed out', (tester) async {
    final signedOutApi = FakeAuthApi();
    final signedOut = controller(signedOutApi, FakeBoundAccountStore());
    await signedOut.restore();
    final t = serving();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogDirectoryProvider.overrideWithValue(dir),
          catalogTransportProvider.overrideWithValue(t),
          catalogParserProvider.overrideWithValue(_parse),
          accountAuthControllerProvider.overrideWithValue(signedOut),
        ],
        child: const MaterialApp(home: CatalogRefreshHost(child: SizedBox())),
      ),
    );
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(t.manifestCalls, 0);
    signedOut.dispose();
    await signedOutApi.dispose();
  });

  testWidgets('waits for cloud backup to be ready, then refreshes', (
    tester,
  ) async {
    api.expired = true;
    expect(auth.cloudBackupReady, isFalse);
    final t = serving();
    await tester.pumpWidget(harness(t));
    await settle(tester);
    expect(t.manifestCalls, 0);

    api.emitSession(accountA);
    await settle(tester);

    expect(auth.cloudBackupReady, isTrue);
    expect(t.manifestCalls, 1);
  });

  testWidgets('switching account scope reloads the shared file', (
    tester,
  ) async {
    final first = serving();
    await tester.pumpWidget(harness(first, key: UniqueKey()));
    await settle(tester);
    expect(first.manifestCalls, 1);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);

    final second = FakeCatalogTransport(
      manifest: () async => throw const CatalogNetworkFailure('network'),
    );
    await tester.pumpWidget(harness(second, key: UniqueKey()));
    await settle(tester);

    expect(find.text('release 1 ready'), findsOneWidget);
    expect(second.manifestCalls, 0, reason: 'fresh shared file, no network');
    expect(File('${dir.path}/snapshot.json').existsSync(), isTrue);
  });
}
