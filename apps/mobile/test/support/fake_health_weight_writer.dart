import 'package:beyondrep/features/health/data/health_weight_writer.dart';
import 'package:beyondrep/features/health/data/health_workout_writer.dart';

/// Scripted [HealthWeightWriter] that records every call; never touches a
/// platform.
class FakeHealthWeightWriter implements HealthWeightWriter {
  FakeHealthWeightWriter({this.isIos = true});

  @override
  final bool isIos;

  bool available = true;
  bool writeAccess = true;
  bool accessGrantedByRequest = true;

  /// Results returned by `write`, consumed in order; when empty a write
  /// succeeds with a generated id.
  final List<HealthWriteResult> writeResults = [];
  bool deleteResult = true;
  Object? deleteError;

  final writes = <({double kg, DateTime at})>[];
  final deletes = <SavedWeight>[];
  int requestAccessCalls = 0;

  /// Runs inside `requestAccess`, for tests that flip state during the prompt.
  void Function()? onRequestAccess;

  var _next = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> hasWriteAccess() async => writeAccess;

  @override
  Future<bool> requestAccess() async {
    requestAccessCalls++;
    onRequestAccess?.call();
    if (accessGrantedByRequest) writeAccess = true;
    return writeAccess;
  }

  @override
  Future<HealthWriteResult> write(double kg, DateTime at) async {
    writes.add((kg: kg, at: at));
    if (writeResults.isNotEmpty) return writeResults.removeAt(0);
    final n = _next++;
    return HealthWeightWriteOk('hk-$n', 'client-$n');
  }

  @override
  Future<bool> delete(SavedWeight saved) async {
    deletes.add(saved);
    if (deleteError != null) throw deleteError!;
    return deleteResult;
  }
}
