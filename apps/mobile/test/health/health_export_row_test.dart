import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/page_header.dart';
import 'package:beyondrep/features/health/application/workout_health_export_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/widgets/health_export_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHealthExportController extends HealthExportController {
  FakeHealthExportController(this.initial);
  HealthExportStatus initial;
  final calls = <String>[];

  @override
  Future<HealthExportStatus> build() async => initial;

  @override
  Future<void> turnOn() async => calls.add('turnOn');

  @override
  Future<void> turnOff() async => calls.add('turnOff');

  @override
  Future<void> openSettings() async => calls.add('openSettings');

  @override
  Future<void> allowWatchHealth() async => calls.add('allowWatchHealth');
}

Future<FakeHealthExportController> pumpRow(
  WidgetTester tester,
  HealthExportStatus status, {
  HealthPlatformKind platform = HealthPlatformKind.appleHealth,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = FakeHealthExportController(status);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [healthExportControllerProvider.overrideWith(() => fake)],
      child: MaterialApp(
        theme: BeyondRepTheme.build(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(children: [HealthExportRow(platform: platform)]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

const _sheetBody =
    'BeyondRep will save each workout you finish on this phone to Apple '
    'Health as Strength training, with its name, start and end. Your past '
    'workouts here are saved too. Heart rate and calories are not included. '
    'Apple Watch workouts are already in Apple Health and are not saved '
    'twice.';

void main() {
  testWidgets('shows Off and opens the sheet', (tester) async {
    await pumpRow(tester, const HealthExportOff());
    expect(find.text('Save workouts to Apple Health'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    await tester.tap(find.text('Save workouts to Apple Health'));
    await tester.pumpAndSettle();
    expect(find.text(_sheetBody), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('Turn on calls turnOn and closes the sheet', (tester) async {
    final fake = await pumpRow(tester, const HealthExportOff());
    await tester.tap(find.text('Save workouts to Apple Health'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['turnOn']);
    expect(find.text(_sheetBody), findsNothing);
  });

  testWidgets('Not now closes the sheet without turning on', (tester) async {
    final fake = await pumpRow(tester, const HealthExportOff());
    await tester.tap(find.text('Save workouts to Apple Health'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
    expect(find.text(_sheetBody), findsNothing);
  });

  testWidgets('On shows saved and waiting counts', (tester) async {
    await pumpRow(
      tester,
      const HealthExportOn(saved: 42, waiting: 3, needsAccess: false),
    );
    expect(find.text('On · 42 saved, 3 waiting'), findsOneWidget);
  });

  testWidgets('On shows only what is non-zero', (tester) async {
    await pumpRow(
      tester,
      const HealthExportOn(saved: 42, waiting: 0, needsAccess: false),
    );
    expect(find.text('On · 42 saved'), findsOneWidget);
    await pumpRow(
      tester,
      const HealthExportOn(saved: 0, waiting: 3, needsAccess: false),
    );
    expect(find.text('On · 3 waiting'), findsOneWidget);
    await pumpRow(
      tester,
      const HealthExportOn(saved: 0, waiting: 0, needsAccess: false),
    );
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('needsAccess shows an On tag and a sheet with two actions', (
    tester,
  ) async {
    final fake = await pumpRow(
      tester,
      const HealthExportOn(saved: 1, waiting: 2, needsAccess: true),
    );
    expect(find.text('Allow access in Settings'), findsOneWidget);
    expect(find.byType(NsTag), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    await tester.tap(find.text('Save workouts to Apple Health'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "BeyondRep can't save workouts to Apple Health until you allow it in "
        'Settings.',
      ),
      findsOneWidget,
    );
    expect(fake.calls, isEmpty);
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['openSettings']);
    expect(find.text('Open Settings'), findsNothing);

    await tester.tap(find.text('Save workouts to Apple Health'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop saving'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['openSettings', 'turnOff']);
  });

  testWidgets('needsAccess sheet says Health Connect on Android', (
    tester,
  ) async {
    await pumpRow(
      tester,
      const HealthExportOn(saved: 0, waiting: 1, needsAccess: true),
      platform: HealthPlatformKind.healthConnect,
    );
    await tester.tap(find.text('Save workouts to Health Connect'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "BeyondRep can't save workouts to Health Connect until you allow it "
        'in Settings.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('uses no raw Switch and a screen reader hears the state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRow(
      tester,
      const HealthExportOn(saved: 42, waiting: 0, needsAccess: false),
    );
    expect(find.byType(Switch), findsNothing);
    final node = tester.getSemantics(find.byType(NsListCard));
    expect(node.label, contains('On · 42 saved'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('Stop saving asks before turning off', (tester) async {
    final fake = await pumpRow(
      tester,
      const HealthExportOn(saved: 1, waiting: 0, needsAccess: false),
    );
    await tester.tap(find.text('Save workouts to Apple Health'));
    await tester.pumpAndSettle();
    expect(find.text('Stop saving workouts?'), findsOneWidget);
    expect(
      find.text(
        'New workouts will no longer be saved to Apple Health. Workouts '
        'already saved stay there.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
    await tester.tap(find.text('Save workouts to Apple Health'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop saving'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['turnOff']);
  });

  testWidgets('Health Connect wording on Android', (tester) async {
    await pumpRow(
      tester,
      const HealthExportOff(),
      platform: HealthPlatformKind.healthConnect,
    );
    expect(find.text('Save workouts to Health Connect'), findsOneWidget);
    await tester.tap(find.text('Save workouts to Health Connect'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('to Health Connect as Strength training'),
      findsOneWidget,
    );
    expect(find.textContaining('Apple'), findsNothing);
  });

  testWidgets('hidden when unavailable', (tester) async {
    await pumpRow(tester, const HealthExportUnavailable());
    expect(find.text('Save workouts to Apple Health'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('no overflow at text scale 2 in ${brightness.name}', (
      tester,
    ) async {
      await pumpRow(
        tester,
        const HealthExportOn(saved: 42, waiting: 3, needsAccess: false),
        brightness: brightness,
        textScale: 2,
        width: 320,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save workouts to Apple Health'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('exportRowOffersHeartRateAccessWhenAWearWatchIsPaired', (
    tester,
  ) async {
    final fake = await pumpRow(
      tester,
      const HealthExportOn(
        saved: 2,
        waiting: 0,
        needsAccess: false,
        offersWatchHealthAccess: true,
      ),
      platform: HealthPlatformKind.healthConnect,
    );
    // The saved count stays visible next to the allow action.
    expect(
      find.text(
        'On · 2 saved · Allow heart rate and calories for watch workouts',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Save workouts to Health Connect'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Without this, watch workouts are not saved to Health Connect.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Allow heart rate and calories'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['allowWatchHealth']);
  });

  testWidgets('Stop saving in the watch sheet asks before turning off', (
    tester,
  ) async {
    final fake = await pumpRow(
      tester,
      const HealthExportOn(
        saved: 2,
        waiting: 1,
        needsAccess: false,
        offersWatchHealthAccess: true,
      ),
      platform: HealthPlatformKind.healthConnect,
    );
    expect(
      find.text(
        'On · 2 saved, 1 waiting · Allow heart rate and calories for watch '
        'workouts',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Save workouts to Health Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop saving'));
    await tester.pumpAndSettle();
    expect(find.text('Stop saving workouts?'), findsOneWidget);
    expect(fake.calls, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
    await tester.tap(find.text('Save workouts to Health Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop saving'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop saving').last);
    await tester.pumpAndSettle();
    expect(fake.calls, ['turnOff']);
  });

  testWidgets('without the offer a tap on an On row still asks to stop', (
    tester,
  ) async {
    await pumpRow(
      tester,
      const HealthExportOn(saved: 2, waiting: 0, needsAccess: false),
      platform: HealthPlatformKind.healthConnect,
    );
    expect(
      find.text('Allow heart rate and calories for watch workouts'),
      findsNothing,
    );
    await tester.tap(find.text('Save workouts to Health Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Stop saving workouts?'), findsOneWidget);
  });
}
