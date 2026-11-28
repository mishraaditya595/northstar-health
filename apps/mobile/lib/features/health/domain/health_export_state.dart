/// Lifecycle of one workout's copy in the health store. Local only; the wire
/// names are what the receipt row stores. See ADR-0014.
enum HealthExportState {
  writing,
  confirmed,
  failedRetryable,
  blocked,
  skippedWatch,
  supersededByWatch,
  deleting,

  /// The copy is gone (deleted, or none was ever there) for a deleted or
  /// watch-linked workout; a final row so no later pass looks again.
  deleted;

  String get wire => name;

  static HealthExportState? fromWire(String value) {
    for (final state in values) {
      if (state.name == value) return state;
    }
    return null;
  }
}
