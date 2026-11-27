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
  DateTime? unconfirmed,
}) => watchStatusOf(
  device: device,
  signedIn: signedIn,
  lastConfirmedAt: confirmed,
  unconfirmedSince: unconfirmed,
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
        _status(signedIn: false, confirmed: _now, unconfirmed: _now),
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
      expect(_status(unconfirmed: _now), isA<WatchWaiting>());
      expect(_status(), isA<WatchWaiting>());
    });

    test('synced with the confirmed time when it is recent', () {
      final at = _now.subtract(const Duration(hours: 3));
      final s = _status(confirmed: at, unconfirmed: _now);
      expect(s, isA<WatchSynced>());
      expect((s as WatchSynced).at, at);
    });

    test('an unconfirmed send exactly 48 hours old is stale', () {
      final at = _now.subtract(const Duration(hours: 60));
      final s = _status(
        confirmed: at,
        unconfirmed: _now.subtract(const Duration(hours: 48)),
      );
      expect(s, isA<WatchStale>());
      expect((s as WatchStale).at, at);
    });

    test('an unconfirmed send 47 hours 59 minutes old is still synced', () {
      final at = _now.subtract(const Duration(hours: 100));
      expect(
        _status(
          confirmed: at,
          unconfirmed: _now.subtract(const Duration(hours: 47, minutes: 59)),
        ),
        isA<WatchSynced>(),
      );
    });

    test('an old confirmation with nothing unconfirmed is synced', () {
      final at = _now.subtract(const Duration(hours: 100));
      expect(_status(confirmed: at), isA<WatchSynced>());
    });

    test('a fresh unconfirmed send after days away is not stale', () {
      final at = _now.subtract(const Duration(hours: 72));
      expect(_status(confirmed: at, unconfirmed: _now), isA<WatchSynced>());
    });

    test('never confirmed stays waiting however old the send', () {
      expect(
        _status(unconfirmed: _now.subtract(const Duration(hours: 90))),
        isA<WatchWaiting>(),
      );
    });
  });

  group('watchSentSummary', () {
    test('lists readiness, health and plans', () {
      expect(
        watchSentSummary(hasReadiness: true, hasHealth: true, planCount: 3),
        'Energy, health, 3 plans',
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
    test(
      'keeps the oldest unconfirmed send per account and clears it',
      () async {
        SharedPreferences.setMockInitialValues({'other': 'kept'});
        final store = await WatchStatusStore.open();
        expect(store.unconfirmedSince('a'), isNull);
        final at = DateTime(2026, 11, 25, 9);
        await store.setUnconfirmedSince('a', at);
        expect(store.unconfirmedSince('a'), at);
        expect(store.unconfirmedSince('b'), isNull);
        await store.clearUnconfirmed('a');
        expect(store.unconfirmedSince('a'), isNull);
        await store.setUnconfirmedSince('a', at);
        await store.clear();
        expect(store.unconfirmedSince('a'), isNull);
        expect(
          (await SharedPreferences.getInstance()).getString('other'),
          'kept',
        );
      },
    );

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
