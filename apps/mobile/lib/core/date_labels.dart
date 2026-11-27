const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Weekday name for a [DateTime.weekday] value.
String weekdayName(DateTime day) => weekdayNames[day.weekday - 1];

/// "TUESDAY · 24 NOV 2026".
String todayEyebrow(DateTime local) =>
    '${weekdayName(local).toUpperCase()} · ${local.day} '
    '${_months[local.month - 1].substring(0, 3).toUpperCase()} ${local.year}';

/// "24 Nov".
String shortDateLabel(DateTime local) =>
    '${local.day} ${_months[local.month - 1].substring(0, 3)}';

/// "Tuesday, 24 November".
String longDayLabel(DateTime local) =>
    '${weekdayName(local)}, ${local.day} ${_months[local.month - 1]}';
