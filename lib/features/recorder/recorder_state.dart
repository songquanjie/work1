enum RecorderState {
  idle,
  recording,
  paused,
  saving,
  saveFailed,
}

/// Button enablement. Async work must also set a busy flag; this is not a debounce.
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
