import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/errors/app_error.dart';
import '../core/utils/time_format.dart';
import '../data/local/recording_database.dart';
import '../models/recording.dart';
import '../services/player_service.dart';
import '../services/recording_file_store.dart';

class RecordingRepository extends ChangeNotifier {
  RecordingRepository({
    required RecordingStore database,
    required RecordingFileStore files,
    required RecordingPlayback playback,
    Uuid? uuid,
  })  : _database = database,
        _files = files,
        _playback = playback,
        _uuid = uuid ?? const Uuid();

  final RecordingStore _database;
  final RecordingFileStore _files;
  final RecordingPlayback _playback;
  final Uuid _uuid;

  List<Recording> recordings = <Recording>[];
  bool loading = false;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    final List<Recording> rows = await _database.findAllNewestFirst();
    recordings = await Future.wait(
      rows.map((Recording row) async {
        final bool missing = !await File(row.localPath).exists();
        return row.copyWith(fileMissing: missing);
      }),
    );
    loading = false;
    notifyListeners();
  }

  Future<Recording> persistStoppedFile({
    required String tempPath,
    required int durationMs,
  }) async {
    final SavedRecording saved = await _files.persistStoppedFile(
      tempPath: tempPath,
      durationMs: durationMs,
    );
    final Recording recording = Recording(
      id: _uuid.v4(),
      name: formatRecordingName(saved.savedAt),
      fileName: p.basename(saved.path),
      localPath: saved.path,
      durationMs: saved.durationMs,
      createdAt: saved.savedAt,
    );
    try {
      await _database.insert(recording);
    } catch (_) {
      final File created = File(saved.path);
      if (await created.exists()) {
        await created.delete();
      }
      throw const AppError(
        code: 'SAVE_FAILED',
        message: '保存失败：无法写入本地记录，请重试。',
      );
    }
    await load();
    return recording;
  }

  Future<void> delete(String id) async {
    final Recording? recording = _byId(id) ?? await _database.findById(id);
    if (recording == null) {
      return;
    }
    await _playback.stopIfPlaying(id);
    final File file = File(recording.localPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        throw const AppError(
          code: 'DELETE_FAILED',
          message: '删除文件失败，请稍后重试。',
        );
      }
    }
    await _database.delete(id);
    await load();
  }

  Recording? _byId(String id) {
    for (final Recording item in recordings) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  @override
  void dispose() {
    unawaited(_database.close());
    super.dispose();
  }
}
