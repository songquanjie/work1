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

/// 列表时长：不足 1 秒也显示 00:01，避免刚停的录音看起来像 00:00。
String formatDurationMs(int durationMs) {
  final int safe = durationMs < 0 ? 0 : durationMs;
  if (safe > 0 && safe < 1000) {
    return '00:01';
  }
  return formatClock(Duration(milliseconds: safe));
}

/// 作业要求的录音名：`录音 YYYY-MM-DD HH:mm`，P0 不提供重命名。
String formatRecordingName(DateTime dateTime) {
  return '录音 ${dateTime.year}-${_twoDigits(dateTime.month)}-${_twoDigits(dateTime.day)} '
      '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}';
}

String formatCreatedAt(DateTime dateTime) {
  return '${dateTime.year}-${_twoDigits(dateTime.month)}-${_twoDigits(dateTime.day)} '
      '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}';
}

/// 把录音器的 dBFS 映射到 0~1。多数真机静音大约在 -45dB。
double amplitudeToLevel(double db) {
  return ((db + 45) / 45).clamp(0.0, 1.0);
}
