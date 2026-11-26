import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beyondrep/core/clock.dart';

void main() {
  testWidgets('local clock is re-sampled when the app resumes', (tester) async {
    final container = ProviderContainer();
    final sub = container.listen(localNowProvider, (_, _) {});
    final first = sub.read();

    await tester.pump(const Duration(milliseconds: 5));
    expect(sub.read(), first);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 5));
    expect(sub.read().isAfter(first), isTrue);
    sub.close();
    container.dispose(); // cancels the midnight timer
  });

  testWidgets('local clock refreshes at the next local midnight', (
    tester,
  ) async {
    var wall = DateTime(2026, 11, 25, 23, 59);
    final container = ProviderContainer(
      overrides: [wallClockProvider.overrideWithValue(() => wall)],
    );
    final sub = container.listen(localNowProvider, (_, _) {});
    expect(sub.read().day, 25);

    // Not yet midnight: nothing changes.
    wall = DateTime(2026, 11, 25, 23, 59, 30);
    await tester.pump(const Duration(seconds: 30));
    expect(sub.read().day, 25);

    // The timer fires at midnight and the clock is read again.
    wall = DateTime(2026, 11, 26, 0, 0, 1);
    await tester.pump(const Duration(seconds: 31));
    expect(sub.read().day, 26);

    // And it schedules the next midnight.
    wall = DateTime(2026, 11, 27, 0, 0, 1);
    await tester.pump(const Duration(hours: 24));
    expect(sub.read().day, 27);

    // Disposing cancels the timer: a pending timer would fail this test.
    sub.close();
    container.dispose();
  });

  test('nextLocalMidnight is built from date components', () {
    expect(
      nextLocalMidnight(DateTime(2026, 11, 25, 23, 59, 59)),
      DateTime(2026, 11, 26),
    );
    expect(nextLocalMidnight(DateTime(2026, 12, 31, 10)), DateTime(2027, 1, 1));
    expect(nextLocalMidnight(DateTime(2026, 11, 25)), DateTime(2026, 11, 26));
  });
}
