import 'package:beyondrep/features/health/data/health_workout_writer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('beyondrep/health_heart_rate');
  final calls = <MethodCall>[];

  void reply(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  final start = DateTime.utc(2026, 11, 20, 9);
  final end = DateTime.utc(2026, 11, 20, 10);
  final samples = [
    HeartRateMinute(at: start, bpm: 71),
    HeartRateMinute(at: start.add(const Duration(minutes: 2)), bpm: 80),
  ];

  Future<HealthWriteResult> write() => const PlatformHeartRateWriter().write(
    clientRecordId: 'wk:heart_rate',
    version: 1700000000001,
    start: start,
    end: end,
    offsetMinutes: 330,
    samples: samples,
  );

  test(
    'write sends one call with every sample and returns the record id',
    () async {
      reply((_) async => 'hc-record');
      final result = await write();
      expect((result as HealthWriteOk).platformRecordId, 'hc-record');
      final call = calls.single;
      expect(call.method, 'write');
      final args = Map<String, Object?>.from(call.arguments as Map);
      expect(args['clientRecordId'], 'wk:heart_rate');
      expect(args['version'], 1700000000001);
      expect(args['startMs'], start.millisecondsSinceEpoch);
      expect(args['endMs'], end.millisecondsSinceEpoch);
      expect(args['offsetSeconds'], 330 * 60);
      expect(args['samples'], [
        [start.millisecondsSinceEpoch, 71],
        [start.add(const Duration(minutes: 2)).millisecondsSinceEpoch, 80],
      ]);
    },
  );

  test('error codes map to denied, unavailable and failed', () async {
    reply((_) async => throw PlatformException(code: 'permission_denied'));
    expect(await write(), isA<HealthWriteDenied>());
    reply((_) async => throw PlatformException(code: 'unavailable'));
    expect(await write(), isA<HealthWriteUnavailable>());
    reply((_) async => throw PlatformException(code: 'failed', message: 'x'));
    expect(await write(), isA<HealthWriteFailed>());
  });

  test('an empty or missing record id is a failure', () async {
    reply((_) async => '');
    expect(await write(), isA<HealthWriteFailed>());
    reply((_) async => null);
    expect(await write(), isA<HealthWriteFailed>());
  });

  test('a missing native handler is unavailable', () async {
    expect(await write(), isA<HealthWriteUnavailable>());
  });

  test('delete sends the client record id', () async {
    reply((_) async => true);
    final result = await const PlatformHeartRateWriter().delete(
      'wk:heart_rate',
    );
    expect(result, isA<HealthWriteOk>());
    expect(calls.single.method, 'delete');
    expect(Map<String, Object?>.from(calls.single.arguments as Map), {
      'clientRecordId': 'wk:heart_rate',
    });
    reply((_) async => throw PlatformException(code: 'failed'));
    expect(
      await const PlatformHeartRateWriter().delete('wk:heart_rate'),
      isA<HealthWriteFailed>(),
    );
  });
}
