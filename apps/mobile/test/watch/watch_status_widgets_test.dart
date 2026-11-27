import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/page_header.dart';
import 'package:beyondrep/core/design/status_line.dart';
import 'package:beyondrep/features/watch/application/watch_status_provider.dart';
import 'package:beyondrep/features/watch/data/watch_status_store.dart';
import 'package:beyondrep/features/watch/domain/watch_status.dart';
import 'package:beyondrep/features/watch/widgets/watch_account_section.dart';
import 'package:beyondrep/features/watch/widgets/watch_status_banner.dart';
import 'package:beyondrep/features/watch/widgets/watch_status_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Friday 27 Nov 2026, 12:00 local.
final _now = DateTime(2026, 11, 27, 12);
final _tuesday = DateTime(2026, 11, 24, 10, 43);
final _todayAt = DateTime(2026, 11, 27, 10, 43);

const _installed = WatchDeviceStatus(
  supported: true,
  paired: true,
  installed: true,
  reachable: true,
);
const _notInstalled = WatchDeviceStatus(
  supported: true,
  paired: true,
  installed: false,
  reachable: false,
);

class _Seeded extends WatchLinkStateNotifier {
  _Seeded(this.initial);
  final WatchLinkState initial;
  @override
  WatchLinkState build() => initial;
}

WatchLinkState _state(
  WatchStatus status, {
  WatchDeviceStatus device = _installed,
  String? summary,
  bool dismissed = false,
}) => WatchLinkState(
  status: status,
  device: device,
  sentSummary: summary,
  installHintDismissed: dismissed,
);

Future<void> _pump(
  WidgetTester tester,
  WatchLinkState state, {
  Brightness brightness = Brightness.light,
  double scale = 1,
  bool section = false,
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: ListView(
            children: [
              const WatchStatusBanner(),
              const Text('Other content'),
              if (section) const WatchAccountSection(),
              const WatchStatusFooter(),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/today/account',
        builder: (_, _) => const Scaffold(body: Text('Account page')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localNowProvider.overrideWithValue(_now),
        watchLinkStateProvider.overrideWith(() => _Seeded(state)),
      ],
      child: MaterialApp.router(
        theme: BeyondRepTheme.build(brightness),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hidden shows nothing on Today or Account', (tester) async {
    await _pump(tester, _state(const WatchHidden()), section: true);
    expect(find.byType(InsightCard), findsNothing);
    expect(find.byType(NsStatusLine), findsNothing);
    expect(find.textContaining('Apple Watch'), findsNothing);
    expect(find.textContaining('watch'), findsNothing);
  });

  testWidgets('not installed shows banner first with the exact copy', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(const WatchNotInstalled(), device: _notInstalled),
    );
    expect(
      find.textContaining(
        "BeyondRep isn't on your watch yet",
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Open the Watch app on this iPhone, find BeyondRep under Available '
        'Apps and tap Install.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('Show me how'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(InsightCard)).dy,
      lessThan(tester.getTopLeft(find.text('Other content')).dy),
    );
    expect(find.byType(NsStatusLine), findsNothing);
  });

  testWidgets('Not now hides the banner and persists', (tester) async {
    await _pump(
      tester,
      _state(const WatchNotInstalled(), device: _notInstalled),
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.byType(InsightCard), findsNothing);
    expect((await WatchStatusStore.open()).installHintDismissed, isTrue);
  });

  testWidgets('a dismissed install banner stays hidden', (tester) async {
    await _pump(
      tester,
      _state(const WatchNotInstalled(), device: _notInstalled, dismissed: true),
    );
    expect(find.byType(InsightCard), findsNothing);
  });

  testWidgets('Show me how opens three steps', (tester) async {
    await _pump(
      tester,
      _state(const WatchNotInstalled(), device: _notInstalled),
    );
    await tester.tap(find.text('Show me how'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Open the Watch app on this iPhone.'), findsOneWidget);
    expect(find.text('Scroll down to Available Apps.'), findsOneWidget);
    expect(find.text('Tap Install next to BeyondRep.'), findsOneWidget);
  });

  testWidgets('stale shows banner with last time', (tester) async {
    await _pump(tester, _state(WatchStale(_tuesday)));
    expect(
      find.textContaining(
        "Your watch hasn't synced since Tue 10:43",
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Open the BeyondRep app on your watch',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.byType(NsStatusLine), findsNothing);
    await tester.tap(find.byType(InsightCard));
    await tester.pumpAndSettle();
    expect(find.text('Account page'), findsOneWidget);
  });

  testWidgets('synced shows footer last and no banner', (tester) async {
    await _pump(tester, _state(WatchSynced(_todayAt)));
    expect(find.byType(InsightCard), findsNothing);
    expect(find.text('Apple Watch · synced Today 10:43 AM'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(NsStatusLine)).dy,
      greaterThan(tester.getTopLeft(find.text('Other content')).dy),
    );
  });

  testWidgets('footer names the day when the sync was not today', (
    tester,
  ) async {
    await _pump(tester, _state(WatchSynced(_tuesday)));
    expect(find.text('Apple Watch · synced Tue 10:43 AM'), findsOneWidget);
  });

  testWidgets('tapping the install banner text opens Account and sync', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(const WatchNotInstalled(), device: _notInstalled),
    );
    await tester.tap(
      find.textContaining("isn't on your watch yet", findRichText: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Account page'), findsOneWidget);
  });

  testWidgets('waiting shows nothing on Today', (tester) async {
    await _pump(tester, _state(const WatchWaiting()));
    expect(find.byType(InsightCard), findsNothing);
    expect(find.byType(NsStatusLine), findsNothing);
  });

  testWidgets('footer opens Account and sync', (tester) async {
    await _pump(tester, _state(WatchSynced(_todayAt)));
    await tester.tap(find.byType(NsStatusLine));
    await tester.pumpAndSettle();
    expect(find.text('Account page'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('banner and footer fit at text scale 2.0 in $brightness', (
      tester,
    ) async {
      for (final state in [
        _state(const WatchNotInstalled(), device: _notInstalled),
        _state(WatchStale(_tuesday)),
        _state(WatchSynced(_todayAt)),
      ]) {
        await _pump(tester, state, brightness: brightness, scale: 2);
        expect(tester.takeException(), isNull);
      }
    });
  }

  group('account section rows per state', () {
    testWidgets('synced', (tester) async {
      await _pump(
        tester,
        _state(WatchSynced(_todayAt), summary: 'Readiness, health, 3 plans'),
        section: true,
      );
      expect(find.text('APPLE WATCH'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('APPLE WATCH')),
        matchesSemantics(label: 'APPLE WATCH', isHeader: true),
      );
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Installed'), findsOneWidget);
      expect(find.text('Today 10:43 AM'), findsOneWidget);
      expect(find.text('Readiness, health, 3 plans'), findsOneWidget);
    });

    testWidgets('not installed', (tester) async {
      await _pump(
        tester,
        _state(const WatchNotInstalled(), device: _notInstalled),
        section: true,
      );
      expect(find.text('Not installed'), findsNWidgets(2));
      expect(find.text('Not synced yet'), findsOneWidget);
    });

    testWidgets('waiting', (tester) async {
      await _pump(tester, _state(const WatchWaiting()), section: true);
      expect(find.text('Waiting for the watch'), findsOneWidget);
      expect(find.text('Installed'), findsOneWidget);
      expect(find.text('Not synced yet'), findsOneWidget);
    });

    testWidgets('stale uses the caution colour for the last time', (
      tester,
    ) async {
      await _pump(tester, _state(WatchStale(_tuesday)), section: true);
      expect(find.text('Not synced recently'), findsOneWidget);
      expect(find.text('Tue 10:43 AM'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('a confirmation more than 6 days old shows a date', (
      tester,
    ) async {
      await _pump(
        tester,
        _state(WatchSynced(DateTime(2026, 11, 20, 10, 43))),
        section: true,
      );
      expect(find.text('20 Nov 10:43 AM'), findsOneWidget);
    });

    testWidgets('exactly 6 days old still shows the weekday', (tester) async {
      await _pump(
        tester,
        _state(WatchSynced(DateTime(2026, 11, 21, 10, 43))),
        section: true,
      );
      expect(find.text('Sat 10:43 AM'), findsOneWidget);
    });

    testWidgets('sent summary row only when something was sent', (
      tester,
    ) async {
      await _pump(tester, _state(const WatchWaiting()), section: true);
      expect(find.text('Sent to watch'), findsNothing);
    });
  });
}
