import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/metric_explanations.dart';
import 'package:beyondrep/features/health/widgets/metric_info_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _platform = HealthPlatformKind.appleHealth;

/// Opens the sheet for [key] from a button inside a one-route app.
Future<GoRouter> _open(
  WidgetTester tester,
  MetricKey key, {
  MetricUsual? usual,
  String? unit,
  bool placeholder = false,
  bool termsLink = true,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showMetricInfo(
                context,
                key,
                platform: _platform,
                usual: usual,
                unit: unit,
                showUsualPlaceholder: placeholder,
                showTermsLink: termsLink,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/health/terms',
        builder: (_, _) => const Scaffold(body: Text('terms page')),
      ),
    ],
  );
  addTearDown(router.dispose);
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: BeyondRepTheme.build(Brightness.light),
      routerConfig: router,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  final rhr = explanationFor(MetricKey.restingHeartRate, _platform);

  testWidgets('shows what, tells and inBeyondRep for restingHeartRate', (
    tester,
  ) async {
    await _open(tester, MetricKey.restingHeartRate);
    expect(find.text(rhr.title), findsOneWidget);
    expect(find.text(rhr.what), findsOneWidget);
    expect(find.text('What it tells you'), findsOneWidget);
    expect(find.text(rhr.tells), findsOneWidget);
    expect(find.text('In BeyondRep'), findsOneWidget);
    expect(find.text(rhr.inBeyondRep), findsOneWidget);
  });

  testWidgets('shows Your usual 55 to 61 bpm and Today 58 when usual given', (
    tester,
  ) async {
    await _open(
      tester,
      MetricKey.restingHeartRate,
      usual: const MetricUsual(low: 55.2, high: 60.8, today: 58),
      unit: 'bpm',
    );
    expect(find.text('Your usual 55 to 61 bpm'), findsOneWidget);
    expect(find.text('Today 58'), findsOneWidget);
    expect(find.byKey(const Key('ns-range-marker')), findsOneWidget);
  });

  testWidgets('shows the 14-day placeholder when usual is null', (
    tester,
  ) async {
    await _open(tester, MetricKey.hrv, placeholder: true);
    expect(
      find.text("We'll show your usual range after 14 days of data."),
      findsOneWidget,
    );
  });

  testWidgets('shows neither usual nor placeholder by default', (tester) async {
    await _open(tester, MetricKey.hrv);
    expect(find.textContaining('Your usual'), findsNothing);
    expect(find.textContaining('14 days of data'), findsNothing);
  });

  testWidgets('steps daily average has no marker', (tester) async {
    await _open(
      tester,
      MetricKey.steps,
      usual: const MetricUsual(low: 6084, high: 6084, dailyAverage: true),
    );
    expect(find.text('Your daily average 6,084'), findsOneWidget);
    expect(find.byKey(const Key('ns-range-marker')), findsNothing);
    expect(find.textContaining(RegExp(r'^Today \d')), findsNothing);
  });

  testWidgets('All health terms opens /health/terms', (tester) async {
    await _open(tester, MetricKey.steps);
    await tester.tap(find.text('All health terms'));
    await tester.pumpAndSettle();
    expect(find.text('terms page'), findsOneWidget);
  });

  testWidgets('link is hidden when showTermsLink is false', (tester) async {
    await _open(tester, MetricKey.steps, termsLink: false);
    expect(find.text('All health terms'), findsNothing);
  });
}
