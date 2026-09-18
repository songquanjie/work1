import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_error.dart';
import '../../models/recording.dart';
import '../../repositories/recording_repository.dart';

/// 只改展示名，不改磁盘文件名，中文不影响上传和转写。
Future<void> showRenameRecordingDialog({
  required BuildContext context,
  required Recording recording,
}) async {
  final String? next = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return _RenameRecordingDialog(initialName: recording.name);
    },
  );
  if (next == null || !context.mounted) {
    return;
  }
  try {
    await context.read<RecordingRepository>().rename(recording.id, next);
  } on AppError catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }
}

/// 控制器跟弹窗同生共死，避免路由还在卸时就把 TextEditingController dispose 掉。
class _RenameRecordingDialog extends StatefulWidget {
  const _RenameRecordingDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameRecordingDialog> createState() => _RenameRecordingDialogState();
}

class _RenameRecordingDialogState extends State<_RenameRecordingDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: RecordingRepository.maxDisplayNameLength,
        decoration: const InputDecoration(
          hintText: '录音名称',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
