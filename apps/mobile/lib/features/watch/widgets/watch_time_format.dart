import 'package:flutter/material.dart';

import '../../../core/date_labels.dart';

/// "10:43 AM" or "10:43", following the device's 12 or 24 hour setting.
String watchTime(BuildContext context, DateTime at) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(at.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// "Today 10:43 AM", "Tue 10:43 AM" for the last 6 days, then "20 Nov 10:43
/// AM": a bare weekday would be read as the wrong week.
String watchDayTime(BuildContext context, DateTime at, DateTime now) {
  final local = at.toLocal();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(local.year, local.month, local.day)).inDays;
  final day = days == 0
      ? 'Today'
      : days <= 6
      ? weekdayName(local).substring(0, 3)
      : shortDateLabel(local);
  return '$day ${watchTime(context, local)}';
}
