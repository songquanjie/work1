import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_error.dart';
import '../../core/utils/time_format.dart';
import '../../models/processing_status.dart';
import '../../models/recording.dart';
import '../../repositories/recording_repository.dart';
import '../playback/recording_playback_bar.dart';
import '../recording_list/rename_recording_dialog.dart';

/// 看转写全文和摘要，并支持试听。摘要失败只重试 LLM，不会重新传音频。
class RecordingDetailPage extends StatelessWidget {
  const RecordingDetailPage({super.key, required this.recordingId});

  final String recordingId;

  Recording? _item(BuildContext context) {
    for (final Recording item
        in context.watch<RecordingRepository>().recordings) {
      if (item.id == recordingId) {
        return item;
      }
    }
    return null;
  }

  Future<void> _copy(BuildContext context, String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制$label')),
      );
    }
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
    final Recording? recording = _item(context);
    if (recording == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('录音详情')),
        body: const Center(child: Text('这条录音已删除')),
      );
    }

    final RecordingRepository repo = context.read<RecordingRepository>();
    final bool busy = recording.status == ProcessingStatus.uploading ||
        recording.status == ProcessingStatus.transcribing;
    final RetryAction retryAction = retryActionFor(
      status: recording.status,
      remoteTaskId: recording.remoteTaskId,
      failedStage: recording.failedStage,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('录音详情')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  recording.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '重命名',
                onPressed: () => unawaited(
                  showRenameRecordingDialog(
                    context: context,
                    recording: recording,
                  ),
                ),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${formatDurationMs(recording.durationMs)}  ·  ${formatCreatedAt(recording.createdAt)}',
          ),
          const SizedBox(height: 8),
          Text(
            recording.statusLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (recording.fileMissing) ...<Widget>[
            const SizedBox(height: 8),
            const Text('本地文件缺失，无法播放或重新上传。'),
          ],
          const SizedBox(height: 12),
          RecordingPlaybackBar(
            recordingId: recording.id,
            path: recording.localPath,
            durationMs: recording.durationMs,
            canPlay: recording.canPlay,
            progressKey: const Key('detail_playback_progress'),
          ),
          if (recording.status == ProcessingStatus.failed &&
              (recording.errorMessage ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(recording.errorMessage!),
          ],
          if (recording.status == ProcessingStatus.pendingUpload ||
              (recording.status == ProcessingStatus.failed &&
                  retryAction == RetryAction.upload)) ...<Widget>[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy || recording.fileMissing
                  ? null
                  : () => unawaited(
                        _guard(context, () => repo.upload(recording.id)),
                      ),
              child: const Text('上传并转写'),
            ),
          ],
          if (recording.status == ProcessingStatus.failed &&
              retryAction == RetryAction.remoteRetry) ...<Widget>[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => unawaited(
                        _guard(context, () => repo.retry(recording.id)),
                      ),
              child: Text(
                recording.failedStage == 'summarizing' ? '重新生成摘要' : '重试处理',
              ),
            ),
          ],
          if ((recording.transcript ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Text('转写全文', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => unawaited(
                    _copy(context, '转写全文', recording.transcript!),
                  ),
                  child: const Text('复制'),
                ),
              ],
            ),
            SelectableText(recording.transcript!),
          ],
          if ((recording.summary ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Text('智能摘要', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => unawaited(
                    _copy(context, '摘要', recording.summary!),
                  ),
                  child: const Text('复制'),
                ),
              ],
            ),
            SelectableText(recording.summary!),
          ],
        ],
      ),
    );
  }
}
