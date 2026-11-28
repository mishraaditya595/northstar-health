import 'package:flutter/foundation.dart';

/// What the watch is called: an iPhone pairs only with an Apple Watch, an
/// Android phone only with Wear OS (spec 4.4).
String watchName(TargetPlatform platform) =>
    platform == TargetPlatform.iOS ? 'Apple Watch' : 'Watch';

/// The same name inside a sentence.
String watchNameInSentence(TargetPlatform platform) =>
    platform == TargetPlatform.iOS ? 'Apple Watch' : 'watch';

/// The three steps to put BeyondRep on a paired watch.
List<String> watchInstallSteps(TargetPlatform platform) =>
    platform == TargetPlatform.iOS
    ? const [
        'Open the Watch app on this iPhone.',
        'Scroll down to Available Apps.',
        'Tap Install next to BeyondRep.',
      ]
    : const [
        'On your watch, open the Play Store.',
        'Scroll to Apps on your phone.',
        'Tap Install next to BeyondRep.',
      ];
