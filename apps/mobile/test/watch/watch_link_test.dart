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
    await const MethodChannelWatchLink().updateContext({
      'account_binding': '{"a":1}',
      'plans_snapshot': '{"b":2}',
    });
    expect(calls.single.method, 'updateContext');
    expect(calls.single.arguments, {
      'account_binding': '{"a":1}',
      'plans_snapshot': '{"b":2}',
    });
  });

  test('transfer sends json', () async {
    handle(null);
    await const MethodChannelWatchLink().transfer('{"type":"x"}');
    expect(calls.single.method, 'transfer');
    expect(calls.single.arguments, {'json': '{"type":"x"}'});
  });

  test('isReachableForUpdates returns what the platform says', () async {
    handle((_) async => true);
    expect(await const MethodChannelWatchLink().isReachableForUpdates(), true);
    handle((_) async => false);
    expect(await const MethodChannelWatchLink().isReachableForUpdates(), false);
    handle((_) async => null);
    expect(await const MethodChannelWatchLink().isReachableForUpdates(), false);
  });

  test('MissingPluginException means unsupported and nothing throws', () async {
    messenger.setMockMethodCallHandler(_channel, null);
    const link = MethodChannelWatchLink();
    expect(await link.isReachableForUpdates(), false);
    await link.updateContext({'a': 'b'});
    await link.transfer('{}');
  });

  test('platform error from updateContext is swallowed', () async {
    handle((_) async => throw PlatformException(code: 'wc_failed'));
    const link = MethodChannelWatchLink();
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
