import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Device local time for date labels. Re-sampled whenever the app resumes
/// (including unlocking the phone), so a page left open overnight does not
/// keep showing yesterday. Tests override it with a fixed value.
final localNowProvider = Provider.autoDispose<DateTime>((ref) {
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  return DateTime.now();
});
