import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The device wall clock. Tests override it.
final wallClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The start of the next local calendar day, built from date components so a
/// daylight-saving day of 23 or 25 hours is still correct.
DateTime nextLocalMidnight(DateTime local) =>
    DateTime(local.year, local.month, local.day + 1);

/// Device local time for date labels. Re-sampled whenever the app resumes
/// (including unlocking the phone) and at the next local midnight, so a page
/// left open overnight does not keep showing yesterday. Tests override it
/// with a fixed value.
final localNowProvider = Provider.autoDispose<DateTime>((ref) {
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  final now = ref.watch(wallClockProvider)();
  final midnight = Timer(
    nextLocalMidnight(now).difference(now),
    ref.invalidateSelf,
  );
  ref.onDispose(midnight.cancel);
  return now;
});
