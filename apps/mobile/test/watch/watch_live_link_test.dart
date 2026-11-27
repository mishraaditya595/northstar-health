import 'package:beyondrep/features/watch/data/watch_live_link.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('beyondrep/watch_live_test');
  late MethodChannelWatchLiveLink link;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    link = MethodChannelWatchLiveLink(channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void answer(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  test(
    'sendState passes the JSON to the platform and returns its answer',
    () async {
      answer((_) => true);
      expect(await link.sendState('{"a":1}'), isTrue);
      expect(calls.single.method, 'sendState');
      expect(calls.single.arguments, {'json': '{"a":1}'});
    },
  );

  test('startWatchApp asks the platform once and returns its answer', () async {
    answer((_) => true);
    expect(await link.startWatchApp(), isTrue);
    expect(calls.single.method, 'startWatchApp');
  });

  test('a missing plugin or a platform error means no live link', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'nope');
        });
    expect(await link.sendState('{}'), isFalse);
    expect(await link.startWatchApp(), isFalse);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(await link.sendState('{}'), isFalse);
    expect(await link.startWatchApp(), isFalse);
  });

  test('the no-op link sends nothing', () async {
    const noop = NoopWatchLiveLink();
    expect(await noop.sendState('{}'), isFalse);
    expect(await noop.startWatchApp(), isFalse);
  });
}
