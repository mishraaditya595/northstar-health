import 'package:flutter/material.dart';

import '../../../core/date_labels.dart';

/// "10:43 AM" or "10:43", following the device's 12 or 24 hour setting.
String watchTime(BuildContext context, DateTime at) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(at.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// "Today 10:43 AM" or "Tue 10:43 AM".
String watchDayTime(BuildContext context, DateTime at, DateTime now) {
  final local = at.toLocal();
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  final day = sameDay ? 'Today' : weekdayName(local).substring(0, 3);
  return '$day ${watchTime(context, local)}';
}
