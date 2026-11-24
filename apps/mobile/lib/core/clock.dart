import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Device local time, sampled when a page first reads it. Tests override it.
final localNowProvider = Provider.autoDispose<DateTime>(
  (ref) => DateTime.now(),
);
