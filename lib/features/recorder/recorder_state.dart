enum RecorderState {
  idle,
  recording,
  paused,
  saving,
  saveFailed,
}

/// 按钮能否点。真正防连点还要看 Controller 的 busy，这里只管录音状态。
class RecorderUiPolicy {
  static bool canStart(RecorderState state) =>
      state == RecorderState.idle || state == RecorderState.saveFailed;

  static bool canPause(RecorderState state) => state == RecorderState.recording;

  static bool canResume(RecorderState state) => state == RecorderState.paused;

  static bool canStop(RecorderState state) =>
      state == RecorderState.recording || state == RecorderState.paused;

  static bool buttonsLocked(RecorderState state) =>
      state == RecorderState.saving;
}
