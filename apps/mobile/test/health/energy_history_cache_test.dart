import 'package:beyondrep/features/health/application/energy_history_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

EnergyHistoryKey _key(String owner, {int day = 27, int scope = 1}) => (
  owner: owner,
  day: DateTime(2026, 11, day),
  connectedAt: DateTime(2026, 11, 1),
  accessScope: scope,
);

void main() {
  test('the same key reads once, a different key replaces the entry', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final cache = c.read(energyHistoryCacheProvider.notifier);
    var reads = 0;
    Future<EnergyHistory> read() async {
      reads++;
      return const EnergyHistory(sleep: []);
    }

    await cache.historyFor(_key('a'), read);
    await cache.historyFor(_key('a'), read);
    expect(reads, 1);
    await cache.historyFor(_key('a', day: 28), read);
    expect(reads, 2);
    await cache.historyFor(_key('b', day: 28), read);
    expect(reads, 3);
    expect(c.read(energyHistoryCacheProvider)!.key.owner, 'b');
    await cache.historyFor(_key('a', day: 28), read);
    expect(reads, 4);
  });

  test('usable needs sleep and one of HRV or resting heart rate', () {
    expect(const EnergyHistory().usable, isFalse);
    expect(const EnergyHistory(sleep: []).usable, isFalse);
    expect(const EnergyHistory(sleep: [], hrv: []).usable, isTrue);
    expect(const EnergyHistory(sleep: [], restingHr: []).usable, isTrue);
    expect(const EnergyHistory(hrv: [], restingHr: []).usable, isFalse);
  });
}
