import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/detail/activity_detail_page.dart';
import 'package:beyondrep/features/health/detail/body_detail_page.dart';
import 'package:beyondrep/features/health/detail/heart_detail_page.dart';
import 'package:beyondrep/features/health/detail/readiness_detail_page.dart';
import 'package:beyondrep/features/health/detail/sleep_detail_page.dart';
import 'package:beyondrep/features/health/widgets/activity_card.dart';
import 'package:beyondrep/features/health/widgets/body_card.dart';
import 'package:beyondrep/features/health/widgets/detail_layout.dart';
import 'package:beyondrep/features/health/widgets/heart_card.dart';
import 'package:beyondrep/features/health/widgets/readiness_card.dart';
import 'package:beyondrep/features/health/widgets/sleep_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_overview.dart';
import '../support/fake_health_reader.dart';
import '../support/health_overview_fixtures.dart';
import 'health_cards_test.dart' show pumpHealth;

Future<void> _pumpDetail(
  WidgetTester tester,
  Widget page, {
  required Size size,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeHealthOverview(FakeHealthOverviewController(overview())),
        healthReaderProvider.overrideWithValue(FakeHealthReader()),
        healthOwnerIdProvider.overrideWithValue('synthetic-owner'),
        healthClockProvider.overrideWithValue(() => overviewReadAt),
        localNowProvider.overrideWithValue(overviewReadAt),
      ],
      child: MaterialApp(
        theme: BeyondRepTheme.build(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide Health lays the five cards in three columns', (
    tester,
  ) async {
    await pumpHealth(tester, overview(), width: 1194, height: 834);
    Offset at(Type t) => tester.getTopLeft(find.byType(t));
    final readiness = at(ReadinessCard);
    final sleep = at(SleepCard);
    final heart = at(HeartCard);
    final activity = at(ActivityCard);
    final body = at(BodyCard);
    expect(sleep.dy, readiness.dy);
    expect(heart.dy, readiness.dy);
    expect(sleep.dx, greaterThan(readiness.dx));
    expect(heart.dx, greaterThan(sleep.dx));
    expect(body.dy, activity.dy);
    expect(activity.dy, greaterThan(readiness.dy));
    expect(activity.dx, readiness.dx);
  });

  testWidgets('narrow Health keeps readiness full width', (tester) async {
    await pumpHealth(tester, overview(), width: 390);
    expect(tester.getSize(find.byType(ReadinessCard)).width, 390 - 32);
  });

  testWidgets('wide sleep detail shows later panels beside the first', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      const SleepDetailPage(),
      size: const Size(1194, 834),
    );
    final panels = find.byType(DetailPanel);
    expect(panels, findsAtLeast(2));
    final first = tester.getTopLeft(panels.at(0));
    final second = tester.getTopLeft(panels.at(1));
    expect(second.dx, greaterThan(first.dx));
  });

  testWidgets('wide health details at 2x text have no overflow', (
    tester,
  ) async {
    for (final page in const <Widget>[
      ReadinessDetailPage(),
      SleepDetailPage(),
      HeartDetailPage(),
      ActivityDetailPage(),
      BodyDetailPage(),
    ]) {
      await _pumpDetail(
        tester,
        page,
        size: const Size(1366, 1024),
        textScale: 2,
      );
      expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
    }
  });
}
