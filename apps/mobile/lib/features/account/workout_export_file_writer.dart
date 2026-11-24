import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'workout_history_export.dart';

/// Deliberate user-initiated OS document export. No analytics, clipboard,
/// external file path from Dart, app-owned permanent cache or upload.
class WorkoutExportFileWriter {
  const WorkoutExportFileWriter({
    this.channel = const MethodChannel('northstar/workout_export'),
  });

  final MethodChannel channel;

  /// Streams [export] into a protected app-private temporary file created by
  /// the platform, then asks the OS picker to save a copy. True only after the
  /// OS reports the file was written. A cancelled picker or a false [proceed]
  /// (checked after streaming, before the picker) returns false and is not
  /// presented as a successful backup. The temporary file is always deleted;
  /// the platform also purges abandoned ones on next launch.
  Future<bool> saveStreamedJson(
    Future<void> Function(Future<void> Function(String chunk) write) export, {
    required bool Function() proceed,
  }) async {
    final File file;
    try {
      final path = await channel.invokeMethod<String>('prepareFile');
      file = File(path ?? '');
    } on PlatformException {
      throw const WorkoutExportException('save_failed');
    } on MissingPluginException {
      throw const WorkoutExportException('save_not_supported');
    }
    // Never recursively delete a folder this workflow does not own.
    final segments = file.path.split('/');
    if (segments.length < 3 ||
        segments.last != 'beyondrep-workouts.json' ||
        !segments[segments.length - 2].startsWith('beyondrep-export-')) {
      throw const WorkoutExportException('invalid_platform_response');
    }
    try {
      final sink = file.openWrite();
      try {
        await export((chunk) async {
          sink.write(chunk);
          // Flush per chunk so buffered output stays one page in size.
          await sink.flush();
        });
      } finally {
        await sink.close();
      }
      if (!proceed()) return false;
      final response = await channel.invokeMethod<String>('saveFile', {
        'name': 'beyondrep-workouts.json',
        'path': file.path,
      });
      if (response == 'saved') return true;
      if (response == 'cancelled') return false;
      throw const WorkoutExportException('invalid_platform_response');
    } on PlatformException {
      throw const WorkoutExportException('save_failed');
    } on MissingPluginException {
      throw const WorkoutExportException('save_not_supported');
    } finally {
      try {
        await file.parent.delete(recursive: true);
      } on FileSystemException {
        // Best effort; platform launch cleanup purges abandoned exports.
      }
    }
  }
}

final workoutExportFileWriterProvider = Provider<WorkoutExportFileWriter>(
  (ref) => const WorkoutExportFileWriter(),
);
