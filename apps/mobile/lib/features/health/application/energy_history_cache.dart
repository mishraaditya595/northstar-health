import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/health_types.dart';

/// What a held history belongs to: one account, one local day, one
/// connection and one access scope. Any change reads again.
typedef EnergyHistoryKey = ({
  String owner,
  DateTime day,
  DateTime? connectedAt,
  int accessScope,
});

/// Sleep, HRV and resting heart rate for the energy tuning. A null list is a
/// read that failed or was not allowed. Held in memory only.
class EnergyHistory {
  const EnergyHistory({this.sleep, this.hrv, this.restingHr});

  final List<SleepSegment>? sleep;
  final List<HealthSample>? hrv;
  final List<HealthSample>? restingHr;

  bool get usable => sleep != null && (hrv != null || restingHr != null);
}

/// Holds the one history read for the current key so a resume re-read does
/// not repeat the three long reads (platform read quota). A new key replaces
/// the held entry, so only one account's data is ever held. Memory only.
class EnergyHistoryCache
    extends Notifier<({EnergyHistoryKey key, Future<EnergyHistory> history})?> {
  @override
  ({EnergyHistoryKey key, Future<EnergyHistory> history})? build() => null;

  Future<EnergyHistory> historyFor(
    EnergyHistoryKey key,
    Future<EnergyHistory> Function() read,
  ) {
    final held = state;
    if (held != null && held.key == key) return held.history;
    final history = read();
    state = (key: key, history: history);
    return history;
  }
}

final energyHistoryCacheProvider =
    NotifierProvider<
      EnergyHistoryCache,
      ({EnergyHistoryKey key, Future<EnergyHistory> history})?
    >(EnergyHistoryCache.new);
