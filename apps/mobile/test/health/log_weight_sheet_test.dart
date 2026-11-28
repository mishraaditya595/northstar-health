import 'dart:async';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/data/health_weight_writer.dart';
import 'package:beyondrep/features/health/data/health_workout_writer.dart';
import 'package:beyondrep/features/health/widgets/log_weight_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_overview.dart';
import '../support/fake_health_reader.dart';
import '../support/fake_health_weight_writer.dart';
import '../support/health_overview_fixtures.dart';

class _GatedWriter extends FakeHealthWeightWriter {
  final gate = Completer<void>();

  @override
  Future<HealthWriteResult> write(double kg, DateTime at) async {
    final result = super.write(kg, at);
    await gate.future;
    return result;
  }
}

/// Lets a test remove the opener widget while the sheet is open.
final _showOpener = ValueNotifier<bool>(true);

BodyOverview _bodyAt(double kg) => BodyOverview(
  weight: (day: DateTime(2026, 11, 24), value: kg),
  weightDaily: [(day: DateTime(2026, 11, 24), value: kg)],
  bodyFat: null,
  weightVsMonth: null,
);

Future<FakeHealthWeightWriter> _pump(
  WidgetTester tester, {
  FakeHealthWeightWriter? writer,
  double? latestKg = 72.4,
  Section<BodyOverview>? body,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  FakeHealthReader? reader,
}) async {
  final fake = writer ?? FakeHealthWeightWriter();
  _showOpener.value = true;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        healthWeightWriterProvider.overrideWithValue(fake),
        healthReaderProvider.overrideWithValue(reader ?? FakeHealthReader()),
        healthOwnerIdProvider.overrideWithValue('synthetic-owner'),
        fakeHealthOverview(
          FakeHealthOverviewController(
            overview(
              body:
                  body ??
                  (latestKg == null
                      ? const SectionGap(MetricGap.noData)
                      : SectionData(_bodyAt(latestKg))),
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: BeyondRepTheme.build(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: _showOpener,
            builder: (context, show, _) => !show
                ? const SizedBox()
                : Consumer(
                    builder: (context, ref, _) {
                      // The pages that open the sheet already watch the overview.
                      ref.watch(healthOverviewProvider);
                      return Center(
                        child: TextButton(
                          onPressed: () => showLogWeightSheet(context, ref),
                          child: const Text('open'),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  testWidgets('sheet opens prefilled with the latest weight as 72.4', (
    tester,
  ) async {
    await _pump(tester, latestKg: 72.4);
    await _open(tester);
    expect(find.text('Log weight'), findsOneWidget);
    expect(find.text('Weight (kg)'), findsOneWidget);
    expect(_fieldText(tester), '72.4');
  });

  testWidgets('sheet opens with an empty field when there is no weight', (
    tester,
  ) async {
    await _pump(tester, latestKg: null);
    await _open(tester);
    expect(_fieldText(tester), '');
  });

  testWidgets('Save with 72.4 writes once, closes and offers Undo', (
    tester,
  ) async {
    final writer = await _pump(tester, latestKg: null);
    await _open(tester);
    await _type(tester, '72.4');
    await _save(tester);
    expect(writer.writes, hasLength(1));
    expect(writer.writes.single.kg, 72.4);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Saved to Apple Health'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('Android saves with Health Connect wording', (tester) async {
    await _pump(tester, writer: FakeHealthWeightWriter(isIos: false));
    await _open(tester);
    await _save(tester);
    expect(find.text('Saved to Health Connect'), findsOneWidget);
  });

  testWidgets('double-tap Save writes once', (tester) async {
    final writer = await _pump(tester);
    await _open(tester);
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(writer.writes, hasLength(1));
  });

  testWidgets('out of range shows the hint and does not write', (tester) async {
    final writer = await _pump(tester);
    await _open(tester);
    await _type(tester, '5');
    await _save(tester);
    expect(find.text('Enter a weight between 20 and 400 kg'), findsOneWidget);
    expect(writer.writes, isEmpty);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('denied keeps the sheet open and Open Settings opens them', (
    tester,
  ) async {
    final reader = FakeHealthReader();
    final writer = FakeHealthWeightWriter()
      ..writeAccess = false
      ..accessGrantedByRequest = false;
    await _pump(tester, writer: writer, reader: reader);
    await _open(tester);
    await _save(tester);
    expect(
      find.text('Allow BeyondRep to write weight in Settings'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Open Settings'));
    await tester.pumpAndSettle();
    expect(reader.openSettingsCalls, 1);
  });

  testWidgets('failed write shows the retry text and keeps the sheet open', (
    tester,
  ) async {
    final writer = FakeHealthWeightWriter()
      ..writeResults.add(const HealthWriteFailed());
    await _pump(tester, writer: writer);
    await _open(tester);
    await _save(tester);
    expect(
      find.text("Couldn't save to Apple Health. Try again."),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    await _save(tester);
    expect(find.text('Saved to Apple Health'), findsOneWidget);
    expect(writer.writes, hasLength(2));
  });

  testWidgets('tapping Undo deletes the entry', (tester) async {
    final writer = await _pump(tester);
    await _open(tester);
    await _save(tester);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(writer.deletes, hasLength(1));
    expect(writer.deletes.single.clientRecordId, 'client-0');
  });

  testWidgets('failed undo tells the person where to delete it', (
    tester,
  ) async {
    final writer = FakeHealthWeightWriter()..deleteResult = false;
    await _pump(tester, writer: writer);
    await _open(tester);
    await _save(tester);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't remove it. Delete it in the Health app."),
      findsOneWidget,
    );
  });

  testWidgets('renders at text scale 2.0 in dark without overflow', (
    tester,
  ) async {
    await _pump(
      tester,
      textScale: 2,
      brightness: Brightness.dark,
      writer: FakeHealthWeightWriter()
        ..writeAccess = false
        ..accessGrantedByRequest = false,
    );
    await _open(tester);
    await _save(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('sheet cannot be dismissed while saving; Save is disabled', (
    tester,
  ) async {
    final writer = _GatedWriter();
    await _pump(tester, writer: writer);
    await _open(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    // Back, barrier tap and drag down all leave the sheet open.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.tapAt(const Offset(195, 20));
    await tester.pump();
    await tester.fling(find.text('Log weight'), const Offset(0, 600), 2000);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    writer.gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Saved to Apple Health'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('snackbar shows although the opener left the tree', (
    tester,
  ) async {
    final writer = _GatedWriter();
    await _pump(tester, writer: writer);
    await _open(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    _showOpener.value = false;
    await tester.pump();
    writer.gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Saved to Apple Health'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(writer.deletes, hasLength(1));
  });

  testWidgets('failed undo message shows although the opener left', (
    tester,
  ) async {
    final writer = FakeHealthWeightWriter()..deleteResult = false;
    await _pump(tester, writer: writer);
    await _open(tester);
    await _save(tester);
    _showOpener.value = false;
    await tester.pump();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't remove it"), findsOneWidget);
  });

  testWidgets('the field stays enabled while saving', (tester) async {
    final writer = _GatedWriter();
    await _pump(tester, writer: writer);
    await _open(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    writer.gate.complete();
    await tester.pumpAndSettle();
  });
}
