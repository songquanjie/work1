import 'package:echonote/services/playback_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primary action: new item starts, playing pauses, paused resumes', () {
    expect(
      PlaybackPolicy.primaryAction(
        isCurrent: false,
        status: PlaybackStatus.idle,
      ),
      PlaybackAction.start,
    );
    expect(
      PlaybackPolicy.primaryAction(
        isCurrent: true,
        status: PlaybackStatus.playing,
      ),
      PlaybackAction.pause,
    );
    expect(
      PlaybackPolicy.primaryAction(
        isCurrent: true,
        status: PlaybackStatus.paused,
      ),
      PlaybackAction.resume,
    );
  });

  test('completed item replays from the start instead of resuming', () {
    expect(
      PlaybackPolicy.primaryAction(
        isCurrent: true,
        status: PlaybackStatus.completed,
      ),
      PlaybackAction.replay,
    );
    expect(PlaybackPolicy.primaryLabel(PlaybackAction.replay), '重新播放');
    expect(PlaybackPolicy.primaryLabel(PlaybackAction.resume), '继续');
  });

  test('progress clamps to 0..1', () {
    expect(
      PlaybackPolicy.progress(
        position: Duration.zero,
        duration: Duration.zero,
      ),
      0,
    );
    expect(
      PlaybackPolicy.progress(
        position: const Duration(seconds: 30),
        duration: const Duration(seconds: 60),
      ),
      0.5,
    );
  });

  test('pause is only valid while actually playing', () {
    expect(PlaybackPolicy.canPause(PlaybackStatus.playing), isTrue);
    expect(PlaybackPolicy.canPause(PlaybackStatus.paused), isFalse);
    expect(PlaybackPolicy.canResume(PlaybackStatus.paused), isTrue);
    expect(PlaybackPolicy.canResume(PlaybackStatus.playing), isFalse);
  });
}
