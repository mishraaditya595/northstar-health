import 'package:beyondrep/features/watch/data/watch_link.dart';
import 'package:beyondrep/features/watch/domain/watch_status.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('beyondrep/watch_link');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void handle(Future<Object?> Function(MethodCall call)? handler) {
    calls.clear();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return handler?.call(call);
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('updateContext sends the map unchanged', () async {
    handle(null);
    await MethodChannelWatchLink().updateContext({
      'account_binding': '{"a":1}',
      'plans_snapshot': '{"b":2}',
    });
    expect(calls.single.method, 'updateContext');
    expect(calls.single.arguments, {
      'account_binding': '{"a":1}',
      'plans_snapshot': '{"b":2}',
    });
  });

  test(
    'a watchStateChanged call from the platform reaches the stream',
    () async {
      handle(null);
      final link = MethodChannelWatchLink();
      var changes = 0;
      final sub = link.watchStateChanges.listen((_) => changes++);
      await messenger.handlePlatformMessage(
        _channel.name,
        _channel.codec.encodeMethodCall(const MethodCall('watchStateChanged')),
        (_) {},
      );
      expect(changes, 1);
      await sub.cancel();
      await messenger.handlePlatformMessage(
        _channel.name,
        _channel.codec.encodeMethodCall(const MethodCall('watchStateChanged')),
        (_) {},
      );
      expect(changes, 1);
    },
  );

  test('transfer sends json', () async {
    handle(null);
    await MethodChannelWatchLink().transfer('{"type":"x"}');
    expect(calls.single.method, 'transfer');
    expect(calls.single.arguments, {'json': '{"type":"x"}'});
  });

  test('isReachableForUpdates returns what the platform says', () async {
    handle((_) async => true);
    expect(await MethodChannelWatchLink().isReachableForUpdates(), true);
    handle((_) async => false);
    expect(await MethodChannelWatchLink().isReachableForUpdates(), false);
    handle((_) async => null);
    expect(await MethodChannelWatchLink().isReachableForUpdates(), false);
  });

  test('MissingPluginException means unsupported and nothing throws', () async {
    messenger.setMockMethodCallHandler(_channel, null);
    final link = MethodChannelWatchLink();
    expect(await link.isReachableForUpdates(), false);
    await link.updateContext({'a': 'b'});
    await link.transfer('{}');
  });

  test('platform error from updateContext is swallowed', () async {
    handle((_) async => throw PlatformException(code: 'wc_failed'));
    final link = MethodChannelWatchLink();
    await link.updateContext({'a': 'b'});
    await link.transfer('{}');
    expect(await link.isReachableForUpdates(), false);
  });

  test('status maps the platform dictionary', () async {
    handle(
      (_) async => {
        'supported': true,
        'paired': true,
        'installed': false,
        'reachable': false,
      },
    );
    final status = await MethodChannelWatchLink().status();
    expect(calls.single.method, 'watchStatus');
    expect(status.supported, true);
    expect(status.paired, true);
    expect(status.installed, false);
    expect(status.reachable, false);
  });

  test('status is unsupported on MissingPluginException', () async {
    messenger.setMockMethodCallHandler(_channel, null);
    expect(
      await MethodChannelWatchLink().status(),
      WatchDeviceStatus.unsupported,
    );
  });

  test(
    'status is unsupported on a platform error or an empty answer',
    () async {
      handle((_) async => throw PlatformException(code: 'wc_failed'));
      expect(
        await MethodChannelWatchLink().status(),
        WatchDeviceStatus.unsupported,
      );
      handle((_) async => null);
      expect(
        await MethodChannelWatchLink().status(),
        WatchDeviceStatus.unsupported,
      );
    },
  );

  test('watchMessage calls arrive on messages', () async {
    handle(null);
    final link = MethodChannelWatchLink();
    final received = <String>[];
    final sub = link.messages.listen(received.add);
    await messenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(
        const MethodCall('watchMessage', '{"a":1}'),
      ),
      (_) {},
    );
    expect(received, ['{"a":1}']);
    await sub.cancel();
    await messenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(
        const MethodCall('watchMessage', '{"b":2}'),
      ),
      (_) {},
    );
    expect(received, ['{"a":1}']);
  });

  test('state changes and messages share the one platform handler', () async {
    handle(null);
    final link = MethodChannelWatchLink();
    var changes = 0;
    final messages = <String>[];
    final a = link.watchStateChanges.listen((_) => changes++);
    final b = link.messages.listen(messages.add);
    await a.cancel();
    // The state-change listener left; messages must still arrive.
    await messenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(const MethodCall('watchMessage', 'x')),
      (_) {},
    );
    expect(messages, ['x']);
    await b.cancel();
    expect(changes, 0);
  });

  test('NoopWatchLink does nothing and is never reachable', () async {
    const link = NoopWatchLink();
    expect(await link.isReachableForUpdates(), false);
    await link.updateContext({'a': 'b'});
    await link.transfer('{}');
    expect(await link.status(), WatchDeviceStatus.unsupported);
    expect(await link.messages.isEmpty, true);
  });
}
