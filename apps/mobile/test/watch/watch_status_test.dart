import 'package:beyondrep/features/watch/data/watch_status_store.dart';
import 'package:beyondrep/features/watch/domain/watch_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _installed = WatchDeviceStatus(
  supported: true,
  paired: true,
  installed: true,
  reachable: true,
);
final _now = DateTime(2026, 11, 27, 12);

WatchStatus _status({
  WatchDeviceStatus device = _installed,
  bool signedIn = true,
  DateTime? confirmed,
  DateTime? sent,
}) => watchStatusOf(
  device: device,
  signedIn: signedIn,
  lastConfirmedAt: confirmed,
  lastSentAt: sent,
  now: _now,
);

void main() {
  group('watchStatusOf', () {
    test('hidden when the device is not supported', () {
      expect(
        _status(device: WatchDeviceStatus.unsupported),
        isA<WatchHidden>(),
      );
    });

    test('hidden when no watch is paired', () {
      expect(
        _status(
          device: const WatchDeviceStatus(
            supported: true,
            paired: false,
            installed: false,
            reachable: false,
          ),
        ),
        isA<WatchHidden>(),
      );
    });

    test('hidden when signed out, whatever the watch says', () {
      expect(
        _status(signedIn: false, confirmed: _now, sent: _now),
        isA<WatchHidden>(),
      );
    });

    test('not installed when paired without the app', () {
      expect(
        _status(
          device: const WatchDeviceStatus(
            supported: true,
            paired: true,
            installed: false,
            reachable: false,
          ),
          confirmed: _now,
        ),
        isA<WatchNotInstalled>(),
      );
    });

    test('waiting when installed and never confirmed', () {
      expect(_status(sent: _now), isA<WatchWaiting>());
      expect(_status(), isA<WatchWaiting>());
    });

    test('synced with the confirmed time when it is recent', () {
      final at = _now.subtract(const Duration(hours: 3));
      final s = _status(confirmed: at, sent: _now);
      expect(s, isA<WatchSynced>());
      expect((s as WatchSynced).at, at);
    });

    test('exactly 48 hours is stale when something newer was sent', () {
      final at = _now.subtract(const Duration(hours: 48));
      final s = _status(confirmed: at, sent: _now);
      expect(s, isA<WatchStale>());
      expect((s as WatchStale).at, at);
    });

    test('47 hours 59 minutes is still synced', () {
      final at = _now.subtract(const Duration(hours: 47, minutes: 59));
      expect(_status(confirmed: at, sent: _now), isA<WatchSynced>());
    });

    test('confirmed after the last send is never stale', () {
      final at = _now.subtract(const Duration(hours: 100));
      expect(
        _status(confirmed: at, sent: at.subtract(const Duration(minutes: 1))),
        isA<WatchSynced>(),
      );
      expect(_status(confirmed: at, sent: at), isA<WatchSynced>());
    });

    test('old confirmation and nothing sent since is synced, not stale', () {
      final at = _now.subtract(const Duration(hours: 100));
      expect(_status(confirmed: at), isA<WatchSynced>());
    });
  });

  group('watchSentSummary', () {
    test('lists readiness, health and plans', () {
      expect(
        watchSentSummary(hasReadiness: true, hasHealth: true, planCount: 3),
        'Readiness, health, 3 plans',
      );
    });

    test('leaves out what was not sent and capitalizes the first word', () {
      expect(
        watchSentSummary(hasReadiness: false, hasHealth: true, planCount: 1),
        'Health, 1 plan',
      );
      expect(
        watchSentSummary(hasReadiness: false, hasHealth: false, planCount: 2),
        '2 plans',
      );
      expect(
        watchSentSummary(hasReadiness: false, hasHealth: false, planCount: 0),
        isNull,
      );
    });
  });

  group('WatchStatusStore', () {
    test('keeps a confirmed time per account and the dismissed flag', () async {
      SharedPreferences.setMockInitialValues({'other': 'kept'});
      final store = await WatchStatusStore.open();
      expect(store.confirmedAt('a'), isNull);
      expect(store.installHintDismissed, isFalse);
      final at = DateTime(2026, 11, 27, 10, 43);
      await store.setConfirmedAt('a', at);
      await store.dismissInstallHint();
      expect(store.confirmedAt('a'), at);
      expect(store.confirmedAt('b'), isNull);
      expect(store.installHintDismissed, isTrue);
    });

    test('clear removes both and nothing else', () async {
      SharedPreferences.setMockInitialValues({'other': 'kept'});
      final store = await WatchStatusStore.open();
      await store.setConfirmedAt('a', DateTime(2026, 11, 27));
      await store.dismissInstallHint();
      await store.clear();
      expect(store.confirmedAt('a'), isNull);
      expect(store.installHintDismissed, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString('other'),
        'kept',
      );
    });
  });
}
