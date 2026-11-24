import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beyondrep/core/clock.dart';

void main() {
  testWidgets('local clock is re-sampled when the app resumes', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(localNowProvider, (_, _) {});
    addTearDown(sub.close);
    final first = sub.read();

    await tester.pump(const Duration(milliseconds: 5));
    expect(sub.read(), first);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 5));
    expect(sub.read().isAfter(first), isTrue);
  });
}
