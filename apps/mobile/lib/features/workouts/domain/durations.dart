/// "45 s", "1 min", "1 min 30 s": the one place seconds become text.
String formatDurationSeconds(int seconds) {
  if (seconds < 60) return '$seconds s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return rest == 0 ? '$minutes min' : '$minutes min $rest s';
}
