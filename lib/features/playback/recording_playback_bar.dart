import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_error.dart';
import '../../core/utils/time_format.dart';
import '../../services/playback_policy.dart';
import '../../services/player_service.dart';
import 'playback_progress_slider.dart';

/// 只听播放器，避免详情页全文随进度条一起重建。
class RecordingPlaybackBar extends StatelessWidget {
  const RecordingPlaybackBar({
    super.key,
    required this.recordingId,
    required this.path,
    required this.durationMs,
    required this.canPlay,
    this.progressKey = const Key('playback_progress'),
  });

  final String recordingId;
  final String path;
  final int durationMs;
  final bool canPlay;
  final Key progressKey;

  Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on AppError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlayerService player = context.watch<PlayerService>();
    final bool current = player.isCurrent(recordingId);
    final PlaybackStatus playbackStatus =
        current ? player.status : PlaybackStatus.idle;
    final PlaybackAction action = PlaybackPolicy.primaryAction(
      isCurrent: current,
      status: playbackStatus,
    );
    final Duration duration = current && player.duration > Duration.zero
        ? player.duration
        : Duration(milliseconds: durationMs);

    return Row(
      children: <Widget>[
        IconButton(
          tooltip: PlaybackPolicy.primaryLabel(action),
          onPressed: canPlay
              ? () => unawaited(
                    _guard(
                      context,
                      () => player.toggle(id: recordingId, path: path),
                    ),
                  )
              : null,
          icon: Icon(
            action == PlaybackAction.pause ? Icons.pause : Icons.play_arrow,
          ),
        ),
        IconButton(
          tooltip: '重新播放',
          onPressed: canPlay
              ? () => unawaited(
                    _guard(
                      context,
                      () => player.replay(id: recordingId, path: path),
                    ),
                  )
              : null,
          icon: const Icon(Icons.replay),
        ),
        Text(
          formatClock(current ? player.position : Duration.zero),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Expanded(
          child: PlaybackProgressSlider(
            key: progressKey,
            position: current ? player.position : Duration.zero,
            duration: duration,
            enabled: canPlay && current,
            onSeek: (Duration value) => unawaited(player.seek(value)),
          ),
        ),
        Text(
          formatClock(duration),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
