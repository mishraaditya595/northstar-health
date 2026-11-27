import 'dart:io';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/train/active_workout_page.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/watch/application/phone_live_session.dart';
import 'package:beyondrep/features/watch/application/watch_status_provider.dart';
import 'package:beyondrep/features/watch/application/watch_sync_controller.dart';
import 'package:beyondrep/features/watch/data/watch_live_link.dart';
import 'package:beyondrep/features/watch/domain/watch_status.dart';
import 'package:beyondrep/features/watch/widgets/phone_discard_confirm_host.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../catalog/catalog_fixtures.dart';
import '../support/fake_health_overview.dart';
import 'fake_watch_live_link.dart';

class _FakeController extends PhoneLiveSessionController {
  bool? resolved;

  @override
  PhoneLiveSessionState build() => const PhoneLiveSessionState();

  void ask() => state = const PhoneLiveSessionState(pendingDiscard: true);

  @override
  void resolveDiscard(bool confirmed) {
    resolved = confirmed;
    state = const PhoneLiveSessionState();
  }
}

class _Stub implements WatchSyncController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Counting extends PhoneLiveSessionController {
  static int builds = 0;

  @override
  PhoneLiveSessionState build() {
    builds++;
    return const PhoneLiveSessionState();
  }
}

class _Link extends WatchLinkStateNotifier {
  _Link(this.installed);
  final bool installed;

  @override
  WatchLinkState build() => WatchLinkState(
    device: WatchDeviceStatus(
      supported: true,
      paired: true,
      installed: installed,
      reachable: true,
    ),
  );
}

void main() {
  group('PhoneDiscardConfirmHost', () {
    testWidgets(
      'asks the phone owner before a watch discard, keep answers no',
      (tester) async {
        final fake = _FakeController();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [phoneLiveSessionProvider.overrideWith(() => fake)],
            child: MaterialApp(
              theme: BeyondRepTheme.build(Brightness.light),
              home: const PhoneDiscardConfirmHost(
                child: Scaffold(body: Text('page')),
              ),
            ),
          ),
        );
        expect(find.text('Discard workout?'), findsNothing);
        fake.ask();
        await tester.pumpAndSettle();
        expect(find.text('Discard workout?'), findsOneWidget);
        expect(find.textContaining('Apple Watch'), findsOneWidget);
        await tester.tap(find.text('Keep training'));
        await tester.pumpAndSettle();
        expect(fake.resolved, isFalse);
        expect(find.text('Discard workout?'), findsNothing);
      },
    );

    testWidgets('confirming answers yes', (tester) async {
      final fake = _FakeController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [phoneLiveSessionProvider.overrideWith(() => fake)],
          child: MaterialApp(
            theme: BeyondRepTheme.build(Brightness.light),
            home: const PhoneDiscardConfirmHost(
              child: Scaffold(body: Text('page')),
            ),
          ),
        ),
      );
      fake.ask();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard workout'));
      await tester.pumpAndSettle();
      expect(fake.resolved, isTrue);
    });
  });

  testWidgets('WatchSyncHost keeps the phone live session built', (
    tester,
  ) async {
    _Counting.builds = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          watchSyncControllerProvider.overrideWith((ref) => _Stub()),
          phoneLiveSessionProvider.overrideWith(_Counting.new),
        ],
        child: const WatchSyncHost(child: SizedBox()),
      ),
    );
    expect(_Counting.builds, 1);
  });

  group('Open on Apple Watch', () {
    late Directory directory;
    late Store store;
    late FakeWatchLiveLink link;
    late ProviderContainer container;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('beyondrep-open-watch-');
      store = Store(getObjectBoxModel(), directory: directory.path);
      link = FakeWatchLiveLink();
    });
    tearDown(() async {
      await link.dispose();
      store.close();
      directory.deleteSync(recursive: true);
    });

    Future<void> show(WidgetTester tester, {required bool installed}) async {
      final router = GoRouter(
        initialLocation: '/train/workout',
        routes: [
          GoRoute(
            path: '/train/workout',
            builder: (_, _) => const ActiveWorkoutPage(),
          ),
          GoRoute(path: '/train', builder: (_, _) => const SizedBox()),
        ],
      );
      addTearDown(router.dispose);
      container = ProviderContainer(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          watchLiveLinkProvider.overrideWithValue(link),
          watchLinkStateProvider.overrideWith(() => _Link(installed)),
          fakeHealthOverview(FakeHealthOverviewController(null)),
          ...catalogTestOverrides(
            state: const CatalogState(status: CatalogStatus.unavailable),
          ),
        ],
      );
      container.read(workoutActionsProvider).startQuick('Synthetic push day');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: BeyondRepTheme.build(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows the action when the watch app is installed and asks it',
      (tester) async {
        await show(tester, installed: true);
        expect(find.text('Open on Apple Watch'), findsOneWidget);
        await tester.tap(find.text('Open on Apple Watch'));
        await tester.pumpAndSettle();
        expect(link.watchAppStarts, 1);
        // The controller's 30 s timer must be gone before the test ends.
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      },
    );

    testWidgets('hides the action when the watch app is not installed', (
      tester,
    ) async {
      await show(tester, installed: false);
      expect(find.text('Open on Apple Watch'), findsNothing);
      expect(link.watchAppStarts, 0);
    });
  });
}
