import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/account/workout_export_file_writer.dart';
import 'package:northstar_health/features/account/workout_history_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('northstar/workout_export');
  const writer = WorkoutExportFileWriter(channel: channel);
  late Directory root;
  late File file;

  Future<void> writeTwoChunks(Future<void> Function(String) write) async {
    await write('{"workouts":[');
    await write(']}');
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('ns-export-test');
    file = File('${root.path}/northstar-export-1/northstar-workouts.json')
      ..createSync(recursive: true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    root.deleteSync(recursive: true);
  });

  void handle(Future<Object?> Function(MethodCall call) save) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'prepareFile') return file.path;
          return save(call);
        });
  }

  test(
    'streams chunks into native temp file, saves, then deletes it',
    () async {
      String? saved;
      handle((call) async {
        expect(call.method, 'saveFile');
        final args = call.arguments as Map<dynamic, dynamic>;
        expect(args['name'], 'northstar-workouts.json');
        expect(args['path'], file.path);
        saved = File(args['path'] as String).readAsStringSync();
        return 'saved';
      });
      expect(
        await writer.saveStreamedJson(writeTwoChunks, proceed: () => true),
        true,
      );
      expect(saved, '{"workouts":[]}');
      expect(file.parent.existsSync(), false);
    },
  );

  test('cancelled destination picker is not claimed as an export', () async {
    handle((_) async => 'cancelled');
    expect(
      await writer.saveStreamedJson(writeTwoChunks, proceed: () => true),
      false,
    );
    expect(file.parent.existsSync(), false);
  });

  test(
    'failed export never opens the picker and deletes partial file',
    () async {
      var saves = 0;
      handle((_) async => saves++);
      await expectLater(
        writer.saveStreamedJson((write) async {
          await write('{"workouts":[');
          throw const WorkoutExportException('session_changed');
        }, proceed: () => true),
        throwsA(isA<WorkoutExportException>()),
      );
      expect(saves, 0);
      expect(file.parent.existsSync(), false);
    },
  );

  test('owner change after streaming skips the picker', () async {
    var saves = 0;
    handle((_) async => saves++);
    expect(
      await writer.saveStreamedJson(writeTwoChunks, proceed: () => false),
      false,
    );
    expect(saves, 0);
    expect(file.parent.existsSync(), false);
  });

  test('native write failure has a generic non-sensitive result', () async {
    handle((_) async {
      throw PlatformException(
        code: 'write_failed',
        message: 'private file location must never leak',
      );
    });
    await expectLater(
      writer.saveStreamedJson(writeTwoChunks, proceed: () => true),
      throwsA(
        isA<WorkoutExportException>().having(
          (e) => e.code,
          'code',
          'save_failed',
        ),
      ),
    );
    expect(file.parent.existsSync(), false);
  });

  test('unexpected native response fails closed', () async {
    handle((_) async => 'maybe');
    await expectLater(
      writer.saveStreamedJson(writeTwoChunks, proceed: () => true),
      throwsA(isA<WorkoutExportException>()),
    );
  });

  test('temp path outside an export folder is rejected untouched', () async {
    final outside = File('${root.path}/other/northstar-workouts.json')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => outside.path);
    await expectLater(
      writer.saveStreamedJson(writeTwoChunks, proceed: () => true),
      throwsA(
        isA<WorkoutExportException>().having(
          (e) => e.code,
          'code',
          'invalid_platform_response',
        ),
      ),
    );
    expect(outside.existsSync(), true);
  });
}
