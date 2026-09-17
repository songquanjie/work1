import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/time_format.dart';
import 'recorder_controller.dart';
import 'recorder_state.dart';

/// 录音页：开始 / 暂停 / 继续 / 停止。返回时若还在录会先停止保存。
class RecorderPage extends StatelessWidget {
  const RecorderPage({
    super.key,
    this.title = '新建录音',
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Consumer<RecorderController>(
      builder: (BuildContext context, RecorderController controller, _) {
        return PopScope(
          canPop: controller.state == RecorderState.idle ||
              controller.state == RecorderState.saveFailed,
          onPopInvokedWithResult: (bool didPop, Object? result) async {
            if (didPop) {
              return;
            }
            if (controller.state == RecorderState.recording ||
                controller.state == RecorderState.paused) {
              await controller.stop();
            }
            if (!context.mounted) {
              return;
            }
            if (controller.state == RecorderState.saveFailed ||
                controller.state == RecorderState.saving) {
              return;
            }
            Navigator.of(context).pop();
          },
          child: RecorderScaffold(
            title: title,
            state: controller.state,
            elapsed: controller.elapsed,
            volumeLevel: controller.volumeLevel,
            errorMessage: controller.errorMessage,
            permanentlyDenied: controller.permanentlyDenied,
            busy: controller.busy,
            onStart: () => unawaited(controller.start()),
            onPause: () => unawaited(controller.pause()),
            onResume: () => unawaited(controller.resume()),
            onStop: () => unawaited(_handleStop(context, controller)),
            onOpenSettings: () => unawaited(controller.openSettings()),
          ),
        );
      },
    );
  }

  Future<void> _handleStop(
    BuildContext context,
    RecorderController controller,
  ) async {
    await controller.stop();
    if (controller.state == RecorderState.idle && context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

class RecorderControlBar extends StatelessWidget {
  const RecorderControlBar({
    super.key,
    required this.state,
    this.busy = false,
    this.onStart,
    this.onPause,
    this.onResume,
    this.onStop,
  });

  final RecorderState state;
  final bool busy;
  final VoidCallback? onStart;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final bool locked = busy || RecorderUiPolicy.buttonsLocked(state);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        _ActionButton(
          key: const Key('recorder_start'),
          label: '开始',
          icon: Icons.fiber_manual_record,
          enabled: !locked && RecorderUiPolicy.canStart(state),
          onPressed: onStart,
        ),
        _ActionButton(
          key: const Key('recorder_pause'),
          label: '暂停',
          icon: Icons.pause,
          enabled: !locked && RecorderUiPolicy.canPause(state),
          onPressed: onPause,
        ),
        _ActionButton(
          key: const Key('recorder_resume'),
          label: '继续',
          icon: Icons.play_arrow,
          enabled: !locked && RecorderUiPolicy.canResume(state),
          onPressed: onResume,
        ),
        _ActionButton(
          key: const Key('recorder_stop'),
          label: '停止',
          icon: Icons.stop,
          enabled: !locked && RecorderUiPolicy.canStop(state),
          onPressed: onStop,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        FilledButton.tonal(
          onPressed: enabled ? onPressed : null,
          child: Icon(icon),
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }
}

class RecorderScaffold extends StatelessWidget {
  const RecorderScaffold({
    super.key,
    required this.state,
    required this.elapsed,
    required this.volumeLevel,
    required this.errorMessage,
    required this.permanentlyDenied,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onOpenSettings,
    this.title = '随身录音笔记',
    this.busy = false,
  });

  final String title;
  final RecorderState state;
  final Duration elapsed;
  final double volumeLevel;
  final String? errorMessage;
  final bool permanentlyDenied;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onOpenSettings;

  String _stateLabel(RecorderState value) {
    switch (value) {
      case RecorderState.idle:
        return '未开始';
      case RecorderState.recording:
        return '录音中';
      case RecorderState.paused:
        return '已暂停';
      case RecorderState.saving:
        return '保存中';
      case RecorderState.saveFailed:
        return '保存失败';
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            Text(_stateLabel(state), style: textTheme.titleMedium),
            const SizedBox(height: 16),
            Text(
              formatClock(elapsed),
              key: const Key('recorder_elapsed'),
              style: textTheme.displayMedium,
            ),
            const SizedBox(height: 24),
            _VolumeMeter(level: volumeLevel),
            const SizedBox(height: 12),
            const Text('音量会随说话强弱变化'),
            const SizedBox(height: 32),
            RecorderControlBar(
              state: state,
              busy: busy,
              onStart: onStart,
              onPause: onPause,
              onResume: onResume,
              onStop: onStop,
            ),
            if (errorMessage != null) ...<Widget>[
              const SizedBox(height: 24),
              Text(errorMessage!, textAlign: TextAlign.center),
            ],
            if (permanentlyDenied) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onOpenSettings,
                child: const Text('前往系统设置'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VolumeMeter extends StatelessWidget {
  const _VolumeMeter({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        key: const Key('volume_meter'),
        minHeight: 12,
        value: level.clamp(0, 1),
      ),
    );
  }
}
