@Tags(['performance'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/features/catalog/data/catalog_file_store.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/catalog/domain/canonical_json.dart';
import 'package:beyondrep/features/catalog/domain/catalog_filter.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/catalog/domain/catalog_parser.dart';
import 'package:beyondrep/features/catalog/domain/catalog_programs.dart';
import 'package:beyondrep/features/catalog/domain/catalog_templates.dart';
import 'package:beyondrep/features/catalog/domain/exercise_choices.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_fixtures.dart';

// Same limit as scripts/catalog_validate.py MAX_SNAPSHOT_BYTES.
const _validatorLimitBytes = 2 * 1024 * 1024;

Duration _median(List<Duration> runs) {
  final sorted = [...runs]..sort();
  return sorted[sorted.length ~/ 2];
}

double _ms(Duration d) => d.inMicroseconds / 1000;

void _report(String line) => stdout.writeln('[catalog-perf] $line');

void main() {
  late Map<String, Object?> json;
  late String text;
  late String sha;

  setUpAll(() {
    // The generated release 4 migration holds the snapshot between the
    // $catalog$ markers: no new dependency, no build step.
    final sql = File(
      '../../supabase/migrations/20261126050000_catalog_release_4.sql',
    ).readAsStringSync();
    final start = sql.indexOf(r'$catalog$') + r'$catalog$'.length;
    final end = sql.indexOf(r'$catalog$', start);
    json = jsonDecode(sql.substring(start, end)) as Map<String, Object?>;
    final bytes = canonicalJsonBytes(json);
    text = utf8.decode(bytes);
    sha = sha256Hex(bytes);
  });

  test('size', () {
    final raw = utf8.encode(text).length;
    final gz = gzip.encode(utf8.encode(text)).length;
    _report(
      'release ${json['release']}: raw $raw bytes, gzip $gz bytes '
      '(${(gz * 100 / raw).toStringAsFixed(1)}%)',
    );
    expect(raw, lessThan(_validatorLimitBytes));
  });

  test('verify, parse and validate references', () {
    final runs = <Duration>[];
    CatalogSnapshot? parsed;
    for (var i = 0; i < 20; i++) {
      final watch = Stopwatch()..start();
      parsed = parseCatalogSnapshot(jsonDecode(text), expectedSha256: sha);
      watch.stop();
      runs.add(watch.elapsed);
    }
    final median = _median(runs);
    _report(
      'jsonDecode + sha256 + parse + references, median of 20: '
      '${_ms(median).toStringAsFixed(1)} ms '
      '(${parsed!.exercises.length} exercises, ${parsed.templates.length} '
      'templates, ${parsed.programs.length} programs)',
    );
    expect(median, lessThan(const Duration(milliseconds: 500)));
  });

  test('cold cache load publishes the snapshot', () async {
    final root = Directory.systemTemp.createTempSync('beyondrep-perf-');
    addTearDown(() => root.deleteSync(recursive: true));
    final cache = Directory('${root.path}/cache');
    final seed = CatalogFileStore(cache);
    await seed.prepare();
    await seed.writeSnapshotText(text);
    await seed.writeLastCheckedAtMs(1);
    final runs = <Duration>[];
    for (var i = 0; i < 5; i++) {
      final repository = CatalogRepository(
        transport: FakeCatalogTransport(
          manifest: () async => throw const SocketException('offline'),
        ),
        store: CatalogFileStore(cache),
        clock: () => DateTime.utc(2026, 11, 26, 12),
      );
      final watch = Stopwatch()..start();
      await repository.load();
      watch.stop();
      expect(repository.state.status, CatalogStatus.ready);
      runs.add(watch.elapsed);
    }
    final median = _median(runs);
    _report(
      'cold load (read files, parse in an isolate, publish), median of 5: '
      '${_ms(median).toStringAsFixed(1)} ms',
    );
    expect(median, lessThan(const Duration(milliseconds: 500)));
  });

  test('search and filters', () {
    final snapshot = parseCatalogSnapshot(jsonDecode(text));
    final choices = buildExerciseChoices(local: const [], catalog: snapshot);
    final alias = snapshot.exercises
        .firstWhere((e) => e.aliases.isNotEmpty)
        .aliases
        .first;
    final queries = [
      'b', 'be', 'ben', 'sq', 'squ', 'dea', 'row', 'cur', 'pre', 'pl', //
      alias, alias.toLowerCase(), 'dumbbell', 'chest', 'glutes',
      'zzzq', 'xx', 'nothing matches this',
    ];
    final runs = <Duration>[];
    var hits = 0;
    for (var i = 0; i < 50; i++) {
      final query = queries[i % queries.length];
      final watch = Stopwatch()..start();
      hits += choices.where((c) => matchesExerciseQuery(c, query)).length;
      watch.stop();
      runs.add(watch.elapsed);
    }
    final worst = runs.reduce((a, b) => a > b ? a : b);
    final median = _median(runs);
    _report(
      'exercise search over ${choices.length} exercises, 50 queries: '
      'median ${_ms(median).toStringAsFixed(3)} ms, worst '
      '${_ms(worst).toStringAsFixed(3)} ms ($hits hits)',
    );
    expect(worst, lessThan(const Duration(milliseconds: 20)));

    final templates = browsableTemplates(snapshot);
    final programs = browsablePrograms(snapshot);
    final filters = [
      const CatalogFilter(),
      const CatalogFilter(goals: {'strength'}),
      const CatalogFilter(equipment: {'barbell', 'dumbbell'}),
      const CatalogFilter(level: 'beginner', query: 'full'),
      const CatalogFilter(daysPerWeek: 3, goals: {'hypertrophy'}),
      const CatalogFilter(query: 'zzzq'),
    ];
    final filterRuns = <Duration>[];
    for (var i = 0; i < 50; i++) {
      final filter = filters[i % filters.length];
      final watch = Stopwatch()..start();
      templates.where((t) => matchesTemplate(t, filter)).length;
      programs.where((p) => matchesProgram(p, filter)).length;
      watch.stop();
      filterRuns.add(watch.elapsed);
    }
    final filterWorst = filterRuns.reduce((a, b) => a > b ? a : b);
    _report(
      'filters over ${templates.length} templates and ${programs.length} '
      'programs, 50 applications: median '
      '${_ms(_median(filterRuns)).toStringAsFixed(3)} ms, worst '
      '${_ms(filterWorst).toStringAsFixed(3)} ms',
    );
    expect(filterWorst, lessThan(const Duration(milliseconds: 20)));
  });
}
