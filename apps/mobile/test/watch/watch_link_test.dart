import 'package:beyondrep/features/watch/data/watch_link.dart';
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

  test('NoopWatchLink does nothing and is never reachable', () async {
    const link = NoopWatchLink();
    expect(await link.isReachableForUpdates(), false);
    await link.updateContext({'a': 'b'});
    await link.transfer('{}');
  });
}
