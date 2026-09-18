import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_error.dart';
import '../../core/utils/time_format.dart';
import '../../models/processing_status.dart';
import '../../models/recording.dart';
import '../../repositories/recording_repository.dart';
import '../../services/playback_policy.dart';
import '../../services/player_service.dart';
import '../playback/playback_progress_slider.dart';
import '../recorder/recorder_controller.dart';
import '../recorder/recorder_page.dart';
import '../recording_detail/recording_detail_page.dart';
import 'rename_recording_dialog.dart';

/// 首页：列表、播放、上传入口。点一行进详情，长按改展示名。
class RecordingListPage extends StatelessWidget {
  const RecordingListPage({super.key});

  Future<void> _confirmDelete(BuildContext context, Recording recording) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除录音'),
          content: Text('确定删除「${recording.name}」吗？此操作不可恢复。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await _guard(
      context,
      () => context.read<RecordingRepository>().delete(recording.id),
    );
  }

  void _openDetail(BuildContext context, String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordingDetailPage(recordingId: id),
      ),
    );
  }

  Future<void> _openRecorder(BuildContext context) async {
    await context.read<PlayerService>().pauseCurrent();
    if (!context.mounted) {
      return;
    }
    final RecorderController controller = context.read<RecorderController>();
    controller.prepareForNewSession();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<RecorderController>.value(
          value: controller,
          child: const RecorderPage(),
        ),
      ),
    );
  }

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
    final RecordingRepository repo = context.watch<RecordingRepository>();
    final PlayerService player = context.watch<PlayerService>();

    return Scaffold(
      appBar: AppBar(title: const Text('随身录音笔记')),
      body: repo.loading && repo.recordings.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : repo.recordings.isEmpty
              ? const Center(child: Text('还没有录音，点右下角开始一条'))
              : ListView.separated(
                  itemCount: repo.recordings.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final Recording item = repo.recordings[index];
                    final bool current = player.isCurrent(item.id);
                    return RecordingListTile(
                      recording: item,
                      isCurrent: current,
                      status: current ? player.status : PlaybackStatus.idle,
                      position: current ? player.position : Duration.zero,
                      duration: current && player.duration > Duration.zero
                          ? player.duration
                          : Duration(milliseconds: item.durationMs),
                      onPlayPause: () => unawaited(
                        _guard(
                          context,
                          () => player.toggle(
                            id: item.id,
                            path: item.localPath,
                          ),
                        ),
                      ),
                      onReplay: () => unawaited(
                        _guard(
                          context,
                          () => player.replay(
                            id: item.id,
                            path: item.localPath,
                          ),
                        ),
                      ),
                      onSeek: (Duration value) => unawaited(player.seek(value)),
                      onDelete: canDeleteRecording(item.status)
                          ? () => _confirmDelete(context, item)
                          : null,
                      onUpload: canUploadRecording(
                                item.status,
                                failedStage: item.failedStage,
                              ) &&
                              !item.fileMissing
                          ? () => unawaited(
                                _guard(
                                  context,
                                  () => context
                                      .read<RecordingRepository>()
                                      .upload(item.id),
                                ),
                              )
                          : null,
                      onOpenDetail: () => _openDetail(context, item.id),
                      onRename: () => unawaited(
                        showRenameRecordingDialog(
                          context: context,
                          recording: item,
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_openRecorder(context)),
        icon: const Icon(Icons.mic),
        label: const Text('新建录音'),
      ),
    );
  }
}

class RecordingListTile extends StatelessWidget {
  const RecordingListTile({
    super.key,
    required this.recording,
    required this.isCurrent,
    required this.status,
    required this.position,
    required this.duration,
    required this.onPlayPause,
    required this.onReplay,
    required this.onSeek,
    this.onDelete,
    this.onUpload,
    this.onOpenDetail,
    this.onRename,
  });

  final Recording recording;
  final bool isCurrent;
  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final VoidCallback onPlayPause;
  final VoidCallback onReplay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onDelete;
  final VoidCallback? onUpload;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final PlaybackAction action = PlaybackPolicy.primaryAction(
      isCurrent: isCurrent,
      status: status,
    );
    final String label = PlaybackPolicy.primaryLabel(action);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: <Widget>[
          ListTile(
            key: Key('recording_${recording.id}'),
            title: Text(
              recording.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${formatDurationMs(recording.durationMs)}  ·  ${formatCreatedAt(recording.createdAt)}  ·  ${recording.statusLabel}'
              '${recording.fileMissing ? '  ·  文件缺失' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: onOpenDetail,
            onLongPress: onRename,
            leading: IconButton(
              tooltip: label,
              onPressed: recording.canPlay ? onPlayPause : null,
              icon: Icon(
                action == PlaybackAction.pause
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
            ),
            trailing: FittedBox(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (onUpload != null)
                    IconButton(
                      tooltip: '上传',
                      onPressed: onUpload,
                      icon: const Icon(Icons.cloud_upload_outlined),
                    ),
                  IconButton(
                    tooltip: '重新播放',
                    onPressed: recording.canPlay ? onReplay : null,
                    icon: const Icon(Icons.replay),
                  ),
                  IconButton(
                    tooltip: '删除',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
          if (isCurrent)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: <Widget>[
                  Text(
                    formatClock(position),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Expanded(
                    child: PlaybackProgressSlider(
                      key: const Key('playback_progress'),
                      position: position,
                      duration: duration,
                      enabled: recording.canPlay,
                      onSeek: onSeek,
                    ),
                  ),
                  Text(
                    formatClock(duration),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

