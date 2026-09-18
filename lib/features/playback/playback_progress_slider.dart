import 'package:flutter/material.dart';

/// 列表和详情共用的播放进度条。拖动时只改本地值，松手再 seek。
class PlaybackProgressSlider extends StatefulWidget {
  const PlaybackProgressSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.enabled,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final bool enabled;
  final ValueChanged<Duration> onSeek;

  @override
  State<PlaybackProgressSlider> createState() => _PlaybackProgressSliderState();
}

class _PlaybackProgressSliderState extends State<PlaybackProgressSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final double max = widget.duration.inMilliseconds <= 0
        ? 1
        : widget.duration.inMilliseconds.toDouble();
    final double value =
        (_dragging ?? widget.position.inMilliseconds.toDouble()).clamp(0, max);
    return Slider(
      value: value,
      max: max,
      onChanged: widget.enabled
          ? (double next) => setState(() => _dragging = next)
          : null,
      onChangeEnd: widget.enabled
          ? (double next) {
              setState(() => _dragging = null);
              widget.onSeek(Duration(milliseconds: next.round()));
            }
          : null,
    );
  }
}
