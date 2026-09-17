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

/// 主按钮该做什么。just_audio 的 play() 要等到暂停/播完才返回，
/// 所以一进入 playing 就要立刻把按钮切成「暂停」，不能等 Future 结束。
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
