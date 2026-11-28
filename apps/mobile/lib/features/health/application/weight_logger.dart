import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../data/health_reader.dart';
import '../data/health_weight_writer.dart';
import '../data/health_workout_writer.dart';
import '../domain/weight_entry.dart';
import 'health_overview.dart';
import 'health_summary_controller.dart';

sealed class WeightSaveResult {
  const WeightSaveResult();
}

final class WeightSaved extends WeightSaveResult {
  const WeightSaved(this.saved);
  final SavedWeight saved;
}

final class WeightInvalid extends WeightSaveResult {
  const WeightInvalid();
}

final class WeightDenied extends WeightSaveResult {
  const WeightDenied();
}

/// Failed, unavailable, no account, or the account changed meanwhile.
final class WeightSaveFailed extends WeightSaveResult {
  const WeightSaveFailed();
}

/// Writes a typed weight to the health store and takes it back again. Lives
/// as long as the app so Undo works after the screen that saved is gone.
class WeightLogger {
  WeightLogger(this._ref);

  final Ref _ref;
  final _undone = <String>{};

  HealthWeightWriter get _writer => _ref.read(healthWeightWriterProvider);

  bool get isIos => _writer.isIos;

  Future<WeightSaveResult> save(String input) async {
    final owner = _ref.read(healthOwnerIdProvider);
    if (owner == null) return const WeightSaveFailed();
    final kg = parseWeightKg(input);
    if (kg == null) return const WeightInvalid();
    final writer = _writer;
    if (!await writer.hasWriteAccess()) {
      await writer.requestAccess();
      if (!await writer.hasWriteAccess()) return const WeightDenied();
    }
    if (_ref.read(healthOwnerIdProvider) != owner) {
      return const WeightSaveFailed();
    }
    final result = await writer.write(kg, _ref.read(wallClockProvider)());
    switch (result) {
      case HealthWeightWriteOk():
        await _refresh();
        return WeightSaved(
          SavedWeight(
            platformRecordId: result.platformRecordId,
            clientRecordId: result.clientRecordId,
          ),
        );
      case HealthWriteDenied():
        return const WeightDenied();
      default:
        return const WeightSaveFailed();
    }
  }

  /// True when the sample is gone (also when it was already undone).
  Future<bool> undo(SavedWeight saved) async {
    if (_undone.contains(saved.clientRecordId)) return true;
    if (!await _writer.delete(saved)) return false;
    _undone.add(saved.clientRecordId);
    await _refresh();
    return true;
  }

  Future<void> openSettings() => _ref.read(healthReaderProvider).openSettings();

  Future<void> _refresh() async {
    try {
      await _ref.read(healthOverviewProvider.notifier).refresh();
    } catch (_) {}
  }
}

final weightLoggerProvider = Provider<WeightLogger>(WeightLogger.new);
