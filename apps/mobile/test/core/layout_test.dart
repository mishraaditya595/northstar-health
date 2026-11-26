import 'package:beyondrep/core/design/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void _size(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

Widget _cell(String key) => SizedBox(key: ValueKey(key), height: 40);

void main() {
  testWidgets('isWideWindow is false at 839 and true at 840', (tester) async {
    late bool wide;
    Widget probe() => MaterialApp(
      home: Builder(
        builder: (context) {
          wide = isWideWindow(context);
          return const SizedBox();
        },
      ),
    );
    _size(tester, 839, 800);
    await tester.pumpWidget(probe());
    expect(wide, isFalse);
    _size(tester, 840, 800);
    await tester.pumpWidget(probe());
    expect(wide, isTrue);
  });

  Future<int> columns(WidgetTester tester, double w, {double scale = 1}) async {
    _size(tester, w, 800);
    await tester.pumpWidget(
      _host(
        NsResponsiveGrid(children: [for (var i = 0; i < 6; i++) _cell('c$i')]),
        textScale: scale,
      ),
    );
    final xs = {
      for (var i = 0; i < 6; i++)
        tester.getTopLeft(find.byKey(ValueKey('c$i'))).dx,
    };
    return xs.length;
  }

  testWidgets(
    'NsResponsiveGrid uses 3 columns at 1040 wide, 2 at 700, 1 at 360',
    (tester) async {
      expect(await columns(tester, 1040), 3);
      expect(await columns(tester, 700), 2);
      expect(await columns(tester, 360), 1);
    },
  );

  testWidgets(
    'NsResponsiveGrid drops to 2 columns at 1040 wide with 2.0 text scale',
    (tester) async {
      expect(await columns(tester, 1040, scale: 2), 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'NsSplitColumns puts side beside main when wide, below main when narrow',
    (tester) async {
      Widget split() =>
          _host(NsSplitColumns(main: [_cell('m')], side: [_cell('s')]));
      _size(tester, 1194, 834);
      await tester.pumpWidget(split());
      var m = tester.getTopLeft(find.byKey(const ValueKey('m')));
      var s = tester.getTopLeft(find.byKey(const ValueKey('s')));
      expect(s.dx, greaterThan(m.dx));
      expect(s.dy, m.dy);
      _size(tester, 390, 844);
      await tester.pumpWidget(split());
      m = tester.getTopLeft(find.byKey(const ValueKey('m')));
      s = tester.getTopLeft(find.byKey(const ValueKey('s')));
      expect(s.dx, m.dx);
      expect(s.dy, greaterThan(m.dy));
    },
  );

  Widget listDetail({Widget? detail, String? route, List<String>? collapsed}) =>
      MaterialApp(
        home: Scaffold(
          body: NsListDetail(
            list: const Text('LIST'),
            detail: detail,
            emptyDetail: const Text('EMPTY'),
            selectedRoute: route,
            onCollapsed: collapsed?.add,
          ),
        ),
      );

  testWidgets('NsListDetail shows emptyDetail when detail is null and wide', (
    tester,
  ) async {
    _size(tester, 1194, 834);
    await tester.pumpWidget(listDetail());
    expect(find.text('LIST'), findsOneWidget);
    expect(find.text('EMPTY'), findsOneWidget);
  });

  testWidgets('NsListDetail shows only the list when narrow', (tester) async {
    _size(tester, 390, 844);
    await tester.pumpWidget(listDetail(detail: const Text('DETAIL')));
    expect(find.text('LIST'), findsOneWidget);
    expect(find.text('EMPTY'), findsNothing);
    expect(find.text('DETAIL'), findsNothing);
  });

  testWidgets(
    'NsListDetail calls onCollapsed once with the selected route when the window narrows',
    (tester) async {
      final collapsed = <String>[];
      _size(tester, 1194, 834);
      await tester.pumpWidget(
        listDetail(
          detail: const Text('DETAIL'),
          route: '/x/1',
          collapsed: collapsed,
        ),
      );
      expect(find.text('DETAIL'), findsOneWidget);
      expect(collapsed, isEmpty);
      _size(tester, 507, 1024);
      await tester.pump();
      await tester.pump();
      expect(collapsed, ['/x/1']);
      await tester.pump();
      expect(collapsed, ['/x/1']);
    },
  );

  testWidgets('openListItem selects when wide and pushes when narrow', (
    tester,
  ) async {
    var selected = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Builder(
            builder: (context) => TextButton(
              onPressed: () => openListItem(
                context,
                route: '/x/1',
                select: () => selected++,
              ),
              child: const Text('tap'),
            ),
          ),
        ),
        GoRoute(path: '/x/:id', builder: (_, _) => const Text('PAGE X')),
      ],
    );
    addTearDown(router.dispose);
    _size(tester, 1194, 834);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('tap'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.text('PAGE X'), findsNothing);

    _size(tester, 390, 844);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('tap'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.text('PAGE X'), findsOneWidget);
  });
}
