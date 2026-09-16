String _twoDigits(int value) => value.toString().padLeft(2, '0');

String formatClock(Duration duration) {
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes.remainder(60);
  final int seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${_twoDigits(hours)}:${_twoDigits(minutes)}:${_twoDigits(seconds)}';
  }
  return '${_twoDigits(minutes)}:${_twoDigits(seconds)}';
}

String formatDurationMs(int durationMs) {
  final int safe = durationMs < 0 ? 0 : durationMs;
  if (safe > 0 && safe < 1000) {
    return '00:01';
  }
  return formatClock(Duration(milliseconds: safe));
}

String formatRecordingName(DateTime dateTime) {
  return '录音 ${dateTime.year}-${_twoDigits(dateTime.month)}-${_twoDigits(dateTime.day)} '
      '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}';
}

String formatCreatedAt(DateTime dateTime) {
  return '${dateTime.year}-${_twoDigits(dateTime.month)}-${_twoDigits(dateTime.day)} '
      '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}';
}

/// Maps recorder dBFS to 0..1. Silence sits near -45 dB on most devices.
double amplitudeToLevel(double db) {
  return ((db + 45) / 45).clamp(0.0, 1.0);
}
