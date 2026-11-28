import 'package:beyondrep/features/watch/domain/watch_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('watchName is Apple Watch on iOS and Watch elsewhere', () {
    expect(watchName(TargetPlatform.iOS), 'Apple Watch');
    expect(watchName(TargetPlatform.android), 'Watch');
  });

  test('watchNameInSentence keeps Apple Watch and lowers the Android one', () {
    expect(watchNameInSentence(TargetPlatform.iOS), 'Apple Watch');
    expect(watchNameInSentence(TargetPlatform.android), 'watch');
  });

  test('watchInstallSteps differ per platform', () {
    expect(watchInstallSteps(TargetPlatform.iOS), [
      'Open the Watch app on this iPhone.',
      'Scroll down to Available Apps.',
      'Tap Install next to BeyondRep.',
    ]);
    expect(watchInstallSteps(TargetPlatform.android), [
      'On your watch, open the Play Store.',
      'Scroll to Apps on your phone.',
      'Tap Install next to BeyondRep.',
    ]);
  });
}
