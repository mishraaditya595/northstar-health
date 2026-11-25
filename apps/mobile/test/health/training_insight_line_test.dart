import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/application/training_insights.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/detail/heart_detail_page.dart';
import 'package:beyondrep/features/health/detail/sleep_detail_page.dart';
import 'package:beyondrep/features/health/domain/training_insights.dart';
import 'package:beyondrep/features/health/health_page.dart';
import 'package:beyondrep/features/health/widgets/training_insight_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_overview.dart';
import '../support/fake_health_reader.dart';
import '../support/fake_health_summary.dart';
import '../support/health_overview_fixtures.dart';

SleepAfterTraining _sleep(int minutes) => SleepAfterTraining(
  afterTraining: Duration(minutes: 420 + minutes),
  otherNights: const Duration(minutes: 420),
  trainingNights: 9,
  otherNightsCount: 17,
);

RestingHrAfterHard _rhr(double diff) => RestingHrAfterHard(
  afterHard: 55 + diff,
  otherDays: 55,
  hardDays: 4,
  otherDaysCount: 22,
);

const _sleepMore = 'You slept 41m more on nights after training';
const _sleepCaption =
    '9 nights after training vs 17 other nights, last 30 days';
const _rhrHigher =
    'Resting HR was 3 bpm higher the morning after your hardest sessions';
const _rhrCaption = '4 mornings vs 22 other days, last 30 days';

class _Insights extends Notifier<TrainingInsights?> {
  _Insights(this.initial);
  final TrainingInsights? initial;

  @override
  TrainingInsights? build() => initial;

  void set(TrainingInsights? v) => state = v;
}

Future<NotifierProvider<_Insights, TrainingInsights?>> _pump(
  WidgetTester tester,
  Widget page,
  TrainingInsights? insights, {
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final source = NotifierProvider<_Insights, TrainingInsights?>(
    () => _Insights(insights),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeHealthSummary(
          FakeHealthSummaryController(
            HealthConnected(
              readAt: overviewReadAt,
              platform: HealthPlatformKind.appleHealth,
            ),
          ),
        ),
        fakeHealthOverview(FakeHealthOverviewController(overview())),
        healthReaderProvider.overrideWithValue(FakeHealthReader()),
        healthOwnerIdProvider.overrideWithValue('synthetic-owner'),
        healthClockProvider.overrideWithValue(() => overviewReadAt),
        trainingInsightsProvider.overrideWith((ref) => ref.watch(source)),
      ],
      child: MaterialApp(
        theme: BeyondRepTheme.build(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return source;
}

Future<void> _seven(WidgetTester tester) async {
  await tester.tap(find.text('7 days'));
  await tester.pumpAndSettle();
}

void main() {
  group('copy', () {
    Future<void> show(WidgetTester tester, Widget line) => tester.pumpWidget(
      MaterialApp(
        theme: BeyondRepTheme.build(Brightness.light),
        home: Scaffold(body: line),
      ),
    );

    testWidgets('sleep more and less', (tester) async {
      await show(tester, TrainingInsightLine.sleep(_sleep(41)));
      expect(
        find.textContaining(_sleepMore, findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(_sleepCaption, findRichText: true),
        findsOneWidget,
      );
      await show(tester, TrainingInsightLine.sleep(_sleep(-41)));
      expect(
        find.textContaining(
          'You slept 41m less on nights after training',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('resting HR higher and lower, rounded', (tester) async {
      await show(tester, TrainingInsightLine.restingHr(_rhr(2.6)));
      expect(
        find.textContaining(_rhrHigher, findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(_rhrCaption, findRichText: true),
        findsOneWidget,
      );
      await show(tester, TrainingInsightLine.restingHr(_rhr(-2.6)));
      expect(
        find.textContaining(
          'Resting HR was 3 bpm lower the morning after your hardest sessions',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('semantics read sentence and caption; no banned words', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await show(tester, TrainingInsightLine.sleep(_sleep(41)));
      expect(
        find.bySemanticsLabel('$_sleepMore. $_sleepCaption'),
        findsOneWidget,
      );
      final all = '$_sleepMore $_rhrHigher'.toLowerCase();
      for (final w in ['cause', 'because', 'diagnos', 'recover', 'ready']) {
        expect(all.contains(w), isFalse, reason: w);
      }
      handle.dispose();
    });
  });

  group('Health tab', () {
    testWidgets('shows sleep first when both are present', (tester) async {
      await _pump(
        tester,
        const HealthPage(),
        TrainingInsights(sleep: _sleep(41), restingHr: _rhr(3)),
      );
      expect(find.text('From your training'), findsOneWidget);
      expect(
        find.textContaining(_sleepMore, findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Resting HR was', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('falls back to resting HR', (tester) async {
      await _pump(
        tester,
        const HealthPage(),
        TrainingInsights(restingHr: _rhr(3)),
      );
      expect(
        find.textContaining(_rhrHigher, findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('null renders nothing', (tester) async {
      await _pump(tester, const HealthPage(), null);
      expect(find.text('From your training'), findsNothing);
      await _pump(tester, const HealthPage(), const TrainingInsights());
      expect(find.text('From your training'), findsNothing);
    });

    testWidgets('account switch to null removes the line', (tester) async {
      final source = await _pump(
        tester,
        const HealthPage(),
        TrainingInsights(sleep: _sleep(41)),
      );
      expect(find.text('From your training'), findsOneWidget);
      ProviderScope.containerOf(tester.element(find.byType(HealthPage)))
          .read(source.notifier)
          .set(null);
      await tester.pumpAndSettle();
      expect(find.text('From your training'), findsNothing);
    });

    testWidgets('text scale 2.0 dark at 390px does not throw', (tester) async {
      await _pump(
        tester,
        const HealthPage(),
        TrainingInsights(sleep: _sleep(41)),
        textScale: 2,
        brightness: Brightness.dark,
      );
      await tester.scrollUntilVisible(
        find.text('From your training'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('From your training'), findsOneWidget);
    });
  });

  group('Sleep detail', () {
    testWidgets('range view shows the sleep insight only', (tester) async {
      await _pump(
        tester,
        const SleepDetailPage(),
        TrainingInsights(sleep: _sleep(-41), restingHr: _rhr(3)),
      );
      expect(
        find.textContaining('You slept', findRichText: true),
        findsNothing,
      );
      await _seven(tester);
      expect(
        find.textContaining(
          'You slept 41m less on nights after training',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Resting HR was', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('null renders nothing; text scale 2.0 dark is fine', (
      tester,
    ) async {
      final source = await _pump(
        tester,
        const SleepDetailPage(),
        TrainingInsights(sleep: _sleep(41)),
        textScale: 2,
        brightness: Brightness.dark,
      );
      await _seven(tester);
      expect(
        find.textContaining(_sleepMore, findRichText: true),
        findsOneWidget,
      );
      ProviderScope.containerOf(tester.element(find.byType(SleepDetailPage)))
          .read(source.notifier)
          .set(null);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('You slept', findRichText: true),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Heart detail', () {
    testWidgets('shows the resting HR insight only', (tester) async {
      await _pump(
        tester,
        const HeartDetailPage(),
        TrainingInsights(sleep: _sleep(41), restingHr: _rhr(3)),
      );
      await _seven(tester);
      expect(
        find.textContaining(_rhrHigher, findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('You slept', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('null renders nothing; text scale 2.0 dark is fine', (
      tester,
    ) async {
      final source = await _pump(
        tester,
        const HeartDetailPage(),
        TrainingInsights(restingHr: _rhr(3)),
        textScale: 2,
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      ProviderScope.containerOf(tester.element(find.byType(HeartDetailPage)))
          .read(source.notifier)
          .set(null);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Resting HR was', findRichText: true),
        findsNothing,
      );
    });
  });
}
