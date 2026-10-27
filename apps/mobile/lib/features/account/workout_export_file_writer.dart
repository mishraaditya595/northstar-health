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

  /// True only after the OS reports the file was written. A cancelled picker
  /// returns false and is not presented as a successful backup.
  Future<bool> saveJson(String json) async {
    try {
      final response = await channel.invokeMethod<String>('saveJson', {
        'name': 'northstar-workouts.json',
        'json': json,
      });
      if (response == 'saved') return true;
      if (response == 'cancelled') return false;
      throw const WorkoutExportException('invalid_platform_response');
    } on PlatformException {
      throw const WorkoutExportException('save_failed');
    } on MissingPluginException {
      throw const WorkoutExportException('save_not_supported');
    }
  }
}

final workoutExportFileWriterProvider = Provider<WorkoutExportFileWriter>(
  (ref) => const WorkoutExportFileWriter(),
);
