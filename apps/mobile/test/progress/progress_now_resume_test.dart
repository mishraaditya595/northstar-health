import 'package:beyondrep/features/progress/workout_history_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('progressNowProvider re-samples the clock on app resume', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(progressNowProvider, (_, _) {});
    addTearDown(sub.close);
    final before = sub.read();

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await tester.pump(const Duration(milliseconds: 1));
    expect(container.read(progressNowProvider).isAfter(before), isTrue);
  });
}
