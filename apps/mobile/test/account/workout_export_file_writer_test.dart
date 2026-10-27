import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/account/workout_export_file_writer.dart';
import 'package:northstar_health/features/account/workout_history_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('northstar/workout_export');
  const writer = WorkoutExportFileWriter(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('explicit native selection writes JSON and reports success', () async {
    var saves = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveJson');
      final args = call.arguments as Map<dynamic, dynamic>;
      expect(args['name'], 'northstar-workouts.json');
      expect(args['json'], '{"workouts":[]}');
      saves++;
      return 'saved';
    });
    expect(await writer.saveJson('{"workouts":[]}'), true);
    expect(saves, 1);
  });

  test('cancelled destination picker is not claimed as an export', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'cancelled');
    expect(await writer.saveJson('{}'), false);
  });

  test('native write failure has a generic non-sensitive result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'write_failed',
        message: 'private file location must never leak',
      );
    });
    await expectLater(
      writer.saveJson('{}'),
      throwsA(isA<WorkoutExportException>()
          .having((e) => e.code, 'code', 'save_failed')),
    );
  });

  test('unexpected native response fails closed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'maybe');
    await expectLater(
      writer.saveJson('{}'),
      throwsA(isA<WorkoutExportException>()),
    );
  });
}
