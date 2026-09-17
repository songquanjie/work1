import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/errors/app_error.dart';
import '../core/utils/time_format.dart';
import '../data/local/recording_database.dart';
import '../data/remote/transcription_api.dart';
import '../models/processing_status.dart';
import '../models/recording.dart';
import '../services/player_service.dart';
import '../services/recording_file_store.dart';
import '../services/task_polling_coordinator.dart';

/// 统一协调文件、SQLite 和远端转写。页面只调这里，不自己发 HTTP。
class RecordingRepository extends ChangeNotifier {
  RecordingRepository({
    required RecordingStore database,
    required RecordingFileStore files,
    required RecordingPlayback playback,
    TranscriptionApi? api,
    Uuid? uuid,
  })  : _database = database,
        _files = files,
        _playback = playback,
        _api = api,
        _uuid = uuid ?? const Uuid() {
    _poller = TaskPollingCoordinator(
      lookup: () => recordings,
      sync: syncRemote,
    );
  }

  final RecordingStore _database;
  final RecordingFileStore _files;
  final RecordingPlayback _playback;
  final TranscriptionApi? _api;
  final Uuid _uuid;
  TaskPollingCoordinator? _poller;
  final Set<String> _busy = <String>{};

  List<Recording> recordings = <Recording>[];
  bool loading = false;

  TaskPollingCoordinator? get poller => _poller;

  /// [recoverInterrupted] 只给冷启动用。保存/删除也会刷新列表，
  /// 不能把此时仍在 [_busy] 里的上传改成失败。
  Future<void> load({bool recoverInterrupted = true}) async {
    loading = true;
    notifyListeners();
    final List<Recording> rows = await _database.findAllNewestFirst();
    final List<Recording> recovered = <Recording>[];
    for (final Recording row in rows) {
      Recording next = row.copyWith(
        fileMissing: !await File(row.localPath).exists(),
      );
      // 上传中途被杀时还没有 remoteTaskId，不收口会永远卡在「上传中」。
      if (recoverInterrupted &&
          !_busy.contains(next.id) &&
          isInterruptedUpload(
            status: next.status,
            remoteTaskId: next.remoteTaskId,
          )) {
        next = next.copyWith(
          status: ProcessingStatus.failed,
          failedStage: 'upload',
          errorCode: 'UPLOAD_INTERRUPTED',
          errorMessage: '上传中断，请重试。',
          pollStale: false,
          updatedAt: DateTime.now(),
        );
        await _database.update(next);
      }
      recovered.add(next);
    }
    recordings = recovered;
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
    final DateTime now = saved.savedAt;
    final Recording recording = Recording(
      id: _uuid.v4(),
      name: formatRecordingName(saved.savedAt),
      fileName: p.basename(saved.path),
      localPath: saved.path,
      durationMs: saved.durationMs,
      createdAt: now,
      updatedAt: now,
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
    await load(recoverInterrupted: false);
    return recording;
  }

  /// 用本地录音 id 当幂等键上传。连点同一条会被 [_busy] 丢掉。
  Future<void> upload(String id) async {
    final TranscriptionApi? api = _api;
    if (api == null) {
      throw const AppError(
        code: 'NOT_CONFIGURED',
        message: '未配置服务地址，无法上传。',
      );
    }
    if (!_busy.add(id)) {
      return;
    }
    try {
      final Recording current = await _require(id);
      if (current.fileMissing || !await File(current.localPath).exists()) {
        throw const AppError(
          code: 'FILE_MISSING',
          message: '找不到录音文件，无法上传。',
        );
      }
      await _persist(
        current.copyWith(
          status: ProcessingStatus.uploading,
          errorCode: null,
          errorMessage: null,
          failedStage: null,
          pollStale: false,
          updatedAt: DateTime.now(),
        ),
      );
      try {
        final RemoteTranscription remote = await _createOrReuse(
          api: api,
          recording: current,
        );
        await applyRemote(current.id, remote);
      } catch (error) {
        // JSON / 文件异常不是 AppError，也必须离开「上传中」，否则不能删也不能重试。
        final AppError mapped = error is AppError
            ? error
            : const AppError(
                code: 'UPLOAD_FAILED',
                message: '上传失败，请稍后重试。',
              );
        final Recording latest = await _require(id);
        await _persist(
          latest.copyWith(
            status: ProcessingStatus.failed,
            failedStage: 'upload',
            errorCode: mapped.code,
            errorMessage: mapped.message,
            updatedAt: DateTime.now(),
          ),
        );
        throw mapped;
      }
    } finally {
      _busy.remove(id);
    }
  }

  /// 摘要失败只打后端 retry，不再传文件。
  Future<void> retry(String id) async {
    final Recording current = await _require(id);
    final RetryAction action = retryActionFor(
      status: current.status,
      remoteTaskId: current.remoteTaskId,
      failedStage: current.failedStage,
    );
    if (action == RetryAction.upload) {
      await upload(id);
      return;
    }
    final TranscriptionApi? api = _api;
    final String? remoteId = current.remoteTaskId;
    if (api == null || remoteId == null) {
      await upload(id);
      return;
    }
    if (!_busy.add(id)) {
      return;
    }
    try {
      await _persist(
        current.copyWith(
          status: ProcessingStatus.transcribing,
          errorCode: null,
          errorMessage: null,
          pollStale: false,
          retryCount: current.retryCount + 1,
          updatedAt: DateTime.now(),
        ),
      );
      try {
        final RemoteTranscription remote = await api.retry(remoteId);
        await applyRemote(id, remote);
      } catch (error) {
        if (error is AppError && error.code == 'TASK_IN_PROGRESS') {
          return;
        }
        final AppError mapped = error is AppError
            ? error
            : const AppError(
                code: 'RETRY_FAILED',
                message: '重试失败，请稍后再试。',
              );
        final Recording latest = await _require(id);
        await _persist(
          latest.copyWith(
            status: ProcessingStatus.failed,
            errorCode: mapped.code,
            errorMessage: mapped.message,
            updatedAt: DateTime.now(),
          ),
        );
        throw mapped;
      }
    } finally {
      _busy.remove(id);
    }
  }

  /// 轮询入口。GET 失败默认当瞬时错误，避免把还在跑的任务打成失败。
  Future<void> syncRemote(Recording item) async {
    final TranscriptionApi? api = _api;
    final String? remoteId = item.remoteTaskId;
    if (api == null || remoteId == null || remoteId.isEmpty) {
      return;
    }
    try {
      final RemoteTranscription remote = await api.getTask(remoteId);
      await applyRemote(item.id, remote);
    } on AppError catch (error) {
      if (isTransientQueryError(error.code)) {
        await markPollStale(item.id);
        return;
      }
      final Recording latest = await _require(item.id);
      await _persist(
        latest.copyWith(
          status: ProcessingStatus.failed,
          errorCode: error.code,
          errorMessage: error.message,
          failedStage: latest.failedStage ?? 'transcribing',
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> applyRemote(String localId, RemoteTranscription task) async {
    final Recording current = await _require(localId);
    final MappedRemoteState mapped = mapRemoteTranscription(task);
    await _persist(
      current.copyWith(
        status: mapped.status,
        processingStage: mapped.processingStage,
        remoteTaskId: task.id,
        transcript: mapped.transcript,
        summary: mapped.summary,
        errorCode: mapped.errorCode,
        errorMessage: mapped.errorMessage,
        failedStage: mapped.failedStage,
        lastCheckedAt: DateTime.now(),
        pollStale: false,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markPollStale(String localId) async {
    final Recording? current = _byId(localId) ?? await _database.findById(localId);
    if (current == null || current.status != ProcessingStatus.transcribing) {
      return;
    }
    recordings = recordings
        .map(
          (Recording item) =>
              item.id == localId ? item.copyWith(pollStale: true) : item,
        )
        .toList();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final Recording? recording = _byId(id) ?? await _database.findById(id);
    if (recording == null) {
      return;
    }
    if (!canDeleteRecording(recording.status)) {
      throw const AppError(
        code: 'DELETE_BLOCKED',
        message: '正在处理中，无法删除。',
      );
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
    await load(recoverInterrupted: false);
  }

  Future<void> _persist(Recording next) async {
    await _database.update(next);
    final bool exists = recordings.any((Recording item) => item.id == next.id);
    if (exists) {
      recordings = recordings
          .map(
            (Recording item) => item.id == next.id
                ? next.copyWith(fileMissing: item.fileMissing)
                : item,
          )
          .toList();
    } else {
      await load(recoverInterrupted: false);
      return;
    }
    notifyListeners();
  }

  Future<Recording> _require(String id) async {
    final Recording? recording = _byId(id) ?? await _database.findById(id);
    if (recording == null) {
      throw const AppError(code: 'NOT_FOUND', message: '找不到这条录音。');
    }
    return recording;
  }

  Recording? _byId(String id) {
    for (final Recording item in recordings) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  /// 第一次超时后再 POST 一次：后端按 clientRecordingId 幂等，能把已建任务拿回来。
  Future<RemoteTranscription> _createOrReuse({
    required TranscriptionApi api,
    required Recording recording,
  }) async {
    try {
      return await api.createOrReuse(
        clientRecordingId: recording.id,
        filePath: recording.localPath,
        fileName: recording.fileName,
      );
    } on AppError catch (error) {
      if (error.code != 'TIMEOUT') {
        rethrow;
      }
      return api.createOrReuse(
        clientRecordingId: recording.id,
        filePath: recording.localPath,
        fileName: recording.fileName,
      );
    }
  }

  @override
  void dispose() {
    _poller?.dispose();
    _api?.dispose();
    unawaited(_database.close());
    super.dispose();
  }
}
