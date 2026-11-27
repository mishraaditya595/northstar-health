/// Lifecycle of one workout's copy in the health store. Local only; the wire
/// names are what the receipt row stores. See ADR-0014.
enum HealthExportState {
  writing,
  confirmed,
  failedRetryable,
  blocked,
  skippedWatch,
  supersededByWatch,
  deleting;

  String get wire => name;

  static HealthExportState? fromWire(String value) {
    for (final state in values) {
      if (state.name == value) return state;
    }
    return null;
  }
}
