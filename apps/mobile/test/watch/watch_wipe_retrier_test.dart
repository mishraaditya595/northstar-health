import 'dart:async';
import 'dart:convert';

import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/features/watch/application/watch_sync_controller.dart';
import 'package:beyondrep/features/watch/application/watch_wipe_retrier.dart';
import 'package:beyondrep/features/watch/data/watch_link.dart';
import 'package:beyondrep/features/watch/data/watch_wipe_queue.dart';
import 'package:beyondrep/features/watch/domain/watch_account_key.dart';
import 'package:beyondrep/features/watch/domain/watch_message.dart';
import 'package:beyondrep/features/watch/domain/watch_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const accountA = '00000000-0000-4000-8000-0000000000a1';
const wipe1 = '77777777-3333-4333-8333-000000000001';
const wipe2 = '77777777-3333-4333-8333-000000000002';

class _Link implements WatchLink {
  bool reachable = true;
  final transfers = <String>[];
  final contexts = <Map<String, String>>[];
  final state = StreamController<void>.broadcast();
  final incoming = StreamController<String>.broadcast();

  @override
  Future<bool> isReachableForUpdates() async => reachable;
  @override
  Future<void> updateContext(Map<String, String> latestByType) async =>
      contexts.add(latestByType);
  @override
  Future<void> transfer(String json) async => transfers.add(json);
  @override
  Stream<void> get watchStateChanges => state.stream;
  @override
  Stream<void> get watchReachabilityChanges => const Stream.empty();
  @override
  Future<WatchDeviceStatus> status() async => WatchDeviceStatus.unsupported;
  @override
  Stream<String> get messages => incoming.stream;
}

class _Ids implements UuidFactory {
  _Ids(this.id);
  final String id;
  @override
  String newId() => id;
}

String _wipeJson(String id) => jsonEncode(
  AccountCleared(
    messageId: id,
    sentAtUtc: '2026-11-27T08:00:00Z',
    accountKey: watchAccountKey(accountA),
    wipeUnsent: true,
  ).toJson(),
);

String _ack(String acked, {String result = 'stored'}) => jsonEncode(
  Ack(
    messageId: '88888888-4444-4444-8444-0000000000aa',
    sentAtUtc: '2026-11-27T08:01:00Z',
    accountKey: watchAccountKey(accountA),
    ackedMessageId: acked,
    result: result,
    reason: result == 'rejected' ? 'invalid' : null,
  ).toJson(),
);

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('WatchWipeQueue', () {
    test('add, pending and remove round-trip', () async {
      final queue = WatchWipeQueue(await SharedPreferences.getInstance());
      expect(queue.pending(), isEmpty);
      await queue.add(
        PendingWatchWipe(messageId: wipe1, json: _wipeJson(wipe1)),
      );
      await queue.add(
        PendingWatchWipe(messageId: wipe2, json: _wipeJson(wipe2)),
      );
      expect(queue.pending().map((w) => w.messageId), [wipe1, wipe2]);
      expect(queue.pending().first.json, _wipeJson(wipe1));
      await queue.remove(wipe1);
      expect(queue.pending().map((w) => w.messageId), [wipe2]);
      await queue.remove('unknown');
      expect(queue.pending(), hasLength(1));
    });

    test('adding the same message id twice keeps one entry', () async {
      final queue = WatchWipeQueue(await SharedPreferences.getInstance());
      await queue.add(
        PendingWatchWipe(messageId: wipe1, json: _wipeJson(wipe1)),
      );
      await queue.add(
        PendingWatchWipe(messageId: wipe1, json: _wipeJson(wipe1)),
      );
      expect(queue.pending(), hasLength(1));
    });

    test('keeps the newest 10', () async {
      final queue = WatchWipeQueue(await SharedPreferences.getInstance());
      for (var i = 0; i < 12; i++) {
        final id = '77777777-3333-4333-8333-${i.toString().padLeft(12, '0')}';
        await queue.add(PendingWatchWipe(messageId: id, json: _wipeJson(id)));
      }
      final ids = queue.pending().map((w) => w.messageId).toList();
      expect(ids, hasLength(10));
      expect(ids.first, endsWith('000000000002'));
      expect(ids.last, endsWith('000000000011'));
    });

    test('a corrupt stored value reads as empty', () async {
      SharedPreferences.setMockInitialValues({
        'watch_link.pending_wipes': 'not json',
      });
      final queue = WatchWipeQueue(await SharedPreferences.getInstance());
      expect(queue.pending(), isEmpty);
    });

    test('holds only the account key HMAC, never the user id', () async {
      final queue = WatchWipeQueue(await SharedPreferences.getInstance());
      await queue.add(
        PendingWatchWipe(messageId: wipe1, json: _wipeJson(wipe1)),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('watch_link.pending_wipes'),
        isNot(contains(accountA)),
      );
    });
  });

  group('announceWatchAccountDeleted', () {
    test('the wipe is persisted even when no watch is reachable', () async {
      final link = _Link()..reachable = false;
      final queue = WatchWipeQueue(await SharedPreferences.getInstance());
      await announceWatchAccountDeleted(
        link: link,
        userId: accountA,
        ids: _Ids(wipe1),
        nowUtc: DateTime.utc(2026, 11, 27, 8),
        queue: Future.value(queue),
      );
      expect(link.transfers, isEmpty);
      expect(link.contexts, isEmpty);
      final pending = queue.pending().single;
      expect(pending.messageId, wipe1);
      final message = WatchMessage.fromJson(
        jsonDecode(pending.json) as Map<String, Object?>,
      ) as AccountCleared;
      expect(message.wipeUnsent, isTrue);
      expect(message.accountKey, watchAccountKey(accountA));
    });

    test(
      'a reachable watch gets the transfer and the context at once',
      () async {
        final link = _Link();
        final queue = WatchWipeQueue(await SharedPreferences.getInstance());
        await announceWatchAccountDeleted(
          link: link,
          userId: accountA,
          ids: _Ids(wipe1),
          nowUtc: DateTime.utc(2026, 11, 27, 8),
          queue: Future.value(queue),
        );
        expect(link.transfers.single, queue.pending().single.json);
        expect(link.contexts.single, {
          'account_cleared': link.transfers.single,
        });
      },
    );

    test('a failing queue never stops the immediate send', () async {
      final link = _Link();
      await announceWatchAccountDeleted(
        link: link,
        userId: accountA,
        ids: _Ids(wipe1),
        nowUtc: DateTime.utc(2026, 11, 27, 8),
        queue: Future<WatchWipeQueue>.error(StateError('prefs unavailable')),
      );
      expect(link.transfers, hasLength(1));
      expect(link.contexts, hasLength(1));
    });
  });

  group('WatchWipeRetrier', () {
    Future<WatchWipeQueue> openWith(List<String> ids) async {
      final queue = WatchWipeQueue(await SharedPreferences.getInstance());
      for (final id in ids) {
        await queue.add(PendingWatchWipe(messageId: id, json: _wipeJson(id)));
      }
      return queue;
    }

    test(
      'a persisted wipe is resent on the next launch and removed on ack',
      () async {
        await openWith([wipe1]);
        // A new process: a new queue and retrier over the same preferences.
        final link = _Link();
        final queue = WatchWipeQueue(await SharedPreferences.getInstance());
        final retrier = WatchWipeRetrier(link: link, queue: Future.value(queue))
          ..start();
        addTearDown(retrier.dispose);
        await _settle();
        expect(link.transfers, [_wipeJson(wipe1)]);
        expect(link.contexts, isEmpty, reason: 'never the context');
        expect(queue.pending(), hasLength(1), reason: 'kept until the ack');
        link.incoming.add(_ack(wipe1));
        await _settle();
        expect(queue.pending(), isEmpty);
      },
    );

    test('not reachable sends nothing and keeps the wipe', () async {
      final queue = await openWith([wipe1]);
      final link = _Link()..reachable = false;
      final retrier = WatchWipeRetrier(link: link, queue: Future.value(queue))
        ..start();
      addTearDown(retrier.dispose);
      await _settle();
      expect(link.transfers, isEmpty);
      expect(queue.pending(), hasLength(1));
    });

    test('a pending wipe is sent once until the watch state changes', () async {
      final queue = await openWith([wipe1]);
      final link = _Link();
      final retrier = WatchWipeRetrier(link: link, queue: Future.value(queue))
        ..start();
      addTearDown(retrier.dispose);
      await _settle();
      await retrier.retry();
      expect(link.transfers, hasLength(1));
    });

    test('a watch state change sends it again', () async {
      final queue = await openWith([wipe1]);
      final link = _Link();
      final retrier = WatchWipeRetrier(link: link, queue: Future.value(queue))
        ..start();
      addTearDown(retrier.dispose);
      await _settle();
      expect(link.transfers, hasLength(1));
      link.state.add(null);
      await _settle();
      expect(link.transfers, hasLength(2));
    });

    test('an unreachable watch that becomes reachable gets the wipe', () async {
      final queue = await openWith([wipe1]);
      final link = _Link()..reachable = false;
      final retrier = WatchWipeRetrier(link: link, queue: Future.value(queue))
        ..start();
      addTearDown(retrier.dispose);
      await _settle();
      link.reachable = true;
      link.state.add(null);
      await _settle();
      expect(link.transfers, [_wipeJson(wipe1)]);
    });

    test('an ack for another message id removes nothing', () async {
      final queue = await openWith([wipe1]);
      final link = _Link();
      final retrier = WatchWipeRetrier(link: link, queue: Future.value(queue))
        ..start();
      addTearDown(retrier.dispose);
      await _settle();
      link.incoming.add(_ack(wipe2));
      await _settle();
      expect(queue.pending(), hasLength(1));
    });

    test('a rejected ack removes nothing', () async {
      final queue = await openWith([wipe1]);
      final link = _Link();
      final retrier = WatchWipeRetrier(link: link, queue: Future.value(queue))
        ..start();
      addTearDown(retrier.dispose);
      await _settle();
      link.incoming.add(_ack(wipe1, result: 'rejected'));
      await _settle();
      expect(queue.pending(), hasLength(1));
    });

    test('a duplicate ack removes the wipe', () async {
      final queue = await openWith([wipe1]);
      final link = _Link();
      final retrier = WatchWipeRetrier(link: link, queue: Future.value(queue))
        ..start();
      addTearDown(retrier.dispose);
      await _settle();
      link.incoming.add(_ack(wipe1, result: 'duplicate'));
      await _settle();
      expect(queue.pending(), isEmpty);
    });

    test('garbage messages are ignored', () async {
      final queue = await openWith([wipe1]);
      final link = _Link();
      final retrier = WatchWipeRetrier(link: link, queue: Future.value(queue))
        ..start();
      addTearDown(retrier.dispose);
      await _settle();
      link.incoming.add('not json');
      await _settle();
      expect(queue.pending(), hasLength(1));
    });

    test('dispose stops listening', () async {
      final queue = await openWith([wipe1]);
      final link = _Link();
      final retrier = WatchWipeRetrier(link: link, queue: Future.value(queue))
        ..start();
      await _settle();
      retrier.dispose();
      link.incoming.add(_ack(wipe1));
      await _settle();
      expect(queue.pending(), hasLength(1));
    });
  });
}
