import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/errors/app_error.dart';

class SavedRecording {
  const SavedRecording({
    required this.path,
    required this.durationMs,
    required this.savedAt,
  });

  final String path;
  final int durationMs;
  final DateTime savedAt;
}

/// Copies then deletes the recorder temp file. A rename can fail while the
/// encoder still has the path open; copy leaves a complete destination first.
class RecordingFileStore {
  Future<SavedRecording> persistStoppedFile({
    required String tempPath,
    required int durationMs,
  }) async {
    final File tempFile = await _waitForFile(tempPath);
    final DateTime now = DateTime.now();
    final String extension = p.extension(tempPath);
    final String fileName = 'recording_${now.millisecondsSinceEpoch}$extension';
    final String finalPath = p.join(p.dirname(tempPath), fileName);
    if (p.normalize(tempPath) != p.normalize(finalPath)) {
      await tempFile.copy(finalPath);
      try {
        await tempFile.delete();
      } catch (_) {
        // Final file is what the list points at; leftover tmp is harmless.
      }
    }
    return SavedRecording(
      path: finalPath,
      durationMs: durationMs,
      savedAt: now,
    );
  }

  Future<File> _waitForFile(String path) async {
    final File file = File(path);
    for (int attempt = 0; attempt < 10; attempt++) {
      if (await file.exists() && await file.length() > 0) {
        return file;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!await file.exists() || await file.length() == 0) {
      throw const AppError(code: 'SAVE_FAILED', message: '保存失败：找不到录音文件。');
    }
    return file;
  }
}
