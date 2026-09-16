enum PlaybackStatus {
  idle,
  playing,
  paused,
  completed,
}

enum PlaybackAction {
  start,
  resume,
  pause,
  replay,
}

/// Decides what the primary control does.
///
/// just_audio's play() future stays pending until pause/stop/complete, so the
/// UI must switch to [PlaybackAction.pause] as soon as status is playing.
class PlaybackPolicy {
  static bool canPause(PlaybackStatus status) =>
      status == PlaybackStatus.playing;

  static bool canResume(PlaybackStatus status) =>
      status == PlaybackStatus.paused;

  static PlaybackAction primaryAction({
    required bool isCurrent,
    required PlaybackStatus status,
  }) {
    if (!isCurrent || status == PlaybackStatus.idle) {
      return PlaybackAction.start;
    }
    switch (status) {
      case PlaybackStatus.playing:
        return PlaybackAction.pause;
      case PlaybackStatus.paused:
        return PlaybackAction.resume;
      case PlaybackStatus.completed:
        return PlaybackAction.replay;
      case PlaybackStatus.idle:
        return PlaybackAction.start;
    }
  }

  static String primaryLabel(PlaybackAction action) {
    switch (action) {
      case PlaybackAction.start:
        return '播放';
      case PlaybackAction.resume:
        return '继续';
      case PlaybackAction.pause:
        return '暂停';
      case PlaybackAction.replay:
        return '重新播放';
    }
  }

  static double progress({
    required Duration position,
    required Duration duration,
  }) {
    final int total = duration.inMilliseconds;
    if (total <= 0) {
      return 0;
    }
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }
}
