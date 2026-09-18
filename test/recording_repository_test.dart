import 'dart:async';
import 'dart:io';

import 'package:echonote/core/errors/app_error.dart';
import 'package:echonote/data/local/recording_database.dart';
import 'package:echonote/data/remote/transcription_api.dart';
import 'package:echonote/models/processing_status.dart';
import 'package:echonote/models/recording.dart';
import 'package:echonote/repositories/recording_repository.dart';
import 'package:echonote/services/player_service.dart';
import 'package:echonote/services/recording_file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class _MemoryStore implements RecordingStore {
  final Map<String, Recording> _rows = <String, Recording>{};

  @override
  Future<void> insert(Recording recording) async {
    _rows[recording.id] = recording;
  }

  @override
  Future<void> update(Recording recording) async {
    _rows[recording.id] = recording;
  }

  @override
  Future<void> delete(String id) async {
    _rows.remove(id);
  }

  @override
  Future<Recording?> findById(String id) async => _rows[id];

  @override
  Future<List<Recording>> findAllNewestFirst() async {
    final List<Recording> items = _rows.values.toList();
    items.sort((Recording a, Recording b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Future<void> close() async {}
}

class _FailingStore implements RecordingStore {
  @override
  Future<void> insert(Recording recording) async {
    throw StateError('disk full');
  }

  @override
  Future<void> update(Recording recording) async {
    throw StateError('disk full');
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Recording?> findById(String id) async => null;

  @override
  Future<List<Recording>> findAllNewestFirst() async => <Recording>[];

  @override
  Future<void> close() async {}
}

class _SilentPlayback implements RecordingPlayback {
  String? stoppedId;

  @override
  Future<void> stopIfPlaying(String id) async {
    stoppedId = id;
  }
}

class _FakeApi extends TranscriptionApi {
  _FakeApi({
    this.onCreate,
    this.onGet,
    this.onRetry,
  }) : super(baseUrl: 'http://127.0.0.1:9');

  Future<RemoteTranscription> Function()? onCreate;
  Future<RemoteTranscription> Function()? onGet;
  Future<RemoteTranscription> Function()? onRetry;
  int createCalls = 0;
  int retryCalls = 0;

  @override
  Future<RemoteTranscription> createOrReuse({
    required String clientRecordingId,
    required String filePath,
    required String fileName,
  }) async {
    createCalls += 1;
    final Future<RemoteTranscription> Function()? handler = onCreate;
    if (handler == null) {
      throw const AppError(code: 'HTTP', message: '未配置');
    }
    return handler();
  }

  @override
  Future<RemoteTranscription> getTask(String remoteId) async {
    final Future<RemoteTranscription> Function()? handler = onGet;
    if (handler == null) {
      throw const AppError(code: 'HTTP', message: '未配置');
    }
    return handler();
  }

  @override
  Future<RemoteTranscription> retry(String remoteId) async {
    retryCalls += 1;
    final Future<RemoteTranscription> Function()? handler = onRetry;
    if (handler == null) {
      throw const AppError(code: 'HTTP', message: '未配置');
    }
    return handler();
  }
}

Future<Recording> _persistSample(RecordingRepository repo, Directory dir) async {
  final String tempPath = p.join(dir.path, 'tmp_1.m4a');
  await File(tempPath).writeAsBytes(const <int>[1, 2, 3]);
  return repo.persistStoppedFile(tempPath: tempPath, durationMs: 1500);
}

void main() {
  test('persist then delete keeps metadata and files in sync', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_repo_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final String tempPath = p.join(dir.path, 'tmp_1.m4a');
    await File(tempPath).writeAsBytes(const <int>[1, 2, 3]);
    final _SilentPlayback playback = _SilentPlayback();
    final RecordingRepository repo = RecordingRepository(
      database: _MemoryStore(),
      files: RecordingFileStore(),
      playback: playback,
      uuid: const Uuid(),
    );
    addTearDown(repo.dispose);

    final Recording saved = await repo.persistStoppedFile(
      tempPath: tempPath,
      durationMs: 1500,
    );
    expect(repo.recordings, hasLength(1));
    expect(saved.name.startsWith('录音 '), isTrue);
    expect(saved.status.name, 'pendingUpload');
    expect(await File(saved.localPath).exists(), isTrue);

    await repo.delete(saved.id);
    expect(playback.stoppedId, saved.id);
    expect(repo.recordings, isEmpty);
    expect(await File(saved.localPath).exists(), isFalse);
  });

  test('persist deletes the audio file if metadata insert fails', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_fail_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final String tempPath = p.join(dir.path, 'tmp_1.m4a');
    await File(tempPath).writeAsBytes(const <int>[1, 2, 3]);
    final RecordingRepository repo = RecordingRepository(
      database: _FailingStore(),
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
    );
    addTearDown(repo.dispose);

    await expectLater(
      repo.persistStoppedFile(tempPath: tempPath, durationMs: 1500),
      throwsA(isA<AppError>()),
    );
    expect(dir.listSync(), isEmpty);
  });

  test('upload keeps local id as clientRecordingId and maps remote queued', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_up_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final _FakeApi api = _FakeApi(
      onCreate: () async => const RemoteTranscription(
        id: 'remote-1',
        status: 'queued',
      ),
    );
    final RecordingRepository repo = RecordingRepository(
      database: _MemoryStore(),
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
      api: api,
    );
    addTearDown(repo.dispose);
    final Recording saved = await _persistSample(repo, dir);

    await repo.upload(saved.id);

    expect(api.createCalls, 1);
    expect(repo.recordings.single.status, ProcessingStatus.transcribing);
    expect(repo.recordings.single.remoteTaskId, 'remote-1');
    expect(repo.recordings.single.processingStage, 'queued');
  });

  test('upload failure stays local and can be retried from upload', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_uf_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final _FakeApi api = _FakeApi(
      onCreate: () async {
        throw const AppError(code: 'NETWORK', message: '网络不可用，请检查连接后重试。');
      },
    );
    final RecordingRepository repo = RecordingRepository(
      database: _MemoryStore(),
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
      api: api,
    );
    addTearDown(repo.dispose);
    final Recording saved = await _persistSample(repo, dir);

    await expectLater(repo.upload(saved.id), throwsA(isA<AppError>()));
    expect(repo.recordings.single.status, ProcessingStatus.failed);
    expect(repo.recordings.single.failedStage, 'upload');
    expect(
      retryActionFor(
        status: repo.recordings.single.status,
        remoteTaskId: repo.recordings.single.remoteTaskId,
        failedStage: repo.recordings.single.failedStage,
      ),
      RetryAction.upload,
    );
  });

  test('summary failure retries remote instead of re-uploading', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_rt_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final _FakeApi api = _FakeApi(
      onRetry: () async => const RemoteTranscription(
        id: 'remote-2',
        status: 'completed',
        transcript: '全文',
        summary: '摘要',
      ),
    );
    final RecordingRepository repo = RecordingRepository(
      database: _MemoryStore(),
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
      api: api,
    );
    addTearDown(repo.dispose);
    final Recording saved = await _persistSample(repo, dir);
    await repo.applyRemote(
      saved.id,
      const RemoteTranscription(
        id: 'remote-2',
        status: 'failed',
        transcript: '全文',
        errorCode: 'LLM_NOT_CONFIGURED',
        message: '未配置摘要服务',
      ),
    );

    await repo.retry(saved.id);

    expect(api.createCalls, 0);
    expect(api.retryCalls, 1);
    expect(repo.recordings.single.status, ProcessingStatus.completed);
    expect(repo.recordings.single.summary, '摘要');
  });

  test('query timeout keeps transcribing and marks poll stale', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_st_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final _FakeApi api = _FakeApi(
      onGet: () async {
        throw const AppError(code: 'TIMEOUT', message: '状态暂时无法更新');
      },
    );
    final RecordingRepository repo = RecordingRepository(
      database: _MemoryStore(),
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
      api: api,
    );
    addTearDown(repo.dispose);
    final Recording saved = await _persistSample(repo, dir);
    await repo.applyRemote(
      saved.id,
      const RemoteTranscription(id: 'remote-3', status: 'transcribing'),
    );

    await repo.syncRemote(repo.recordings.single);

    expect(repo.recordings.single.status, ProcessingStatus.transcribing);
    expect(repo.recordings.single.pollStale, isTrue);
    expect(repo.recordings.single.statusLabel, '状态暂时无法更新');
  });

  test('query server error keeps transcribing instead of failing', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_5xx_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final _FakeApi api = _FakeApi(
      onGet: () async {
        throw const AppError(code: 'INTERNAL_ERROR', message: '服务暂时不可用，请稍后重试。');
      },
    );
    final RecordingRepository repo = RecordingRepository(
      database: _MemoryStore(),
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
      api: api,
    );
    addTearDown(repo.dispose);
    final Recording saved = await _persistSample(repo, dir);
    await repo.applyRemote(
      saved.id,
      const RemoteTranscription(id: 'remote-5xx', status: 'summarizing'),
    );

    await repo.syncRemote(repo.recordings.single);

    expect(repo.recordings.single.status, ProcessingStatus.transcribing);
    expect(repo.recordings.single.pollStale, isTrue);
  });

  test('upload timeout retries once and reuses the same client id', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_to_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    int attempts = 0;
    final _FakeApi api = _FakeApi(
      onCreate: () async {
        attempts += 1;
        if (attempts == 1) {
          throw const AppError(code: 'TIMEOUT', message: '上传超时，请重试。');
        }
        return const RemoteTranscription(id: 'remote-to', status: 'queued');
      },
    );
    final RecordingRepository repo = RecordingRepository(
      database: _MemoryStore(),
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
      api: api,
    );
    addTearDown(repo.dispose);
    final Recording saved = await _persistSample(repo, dir);

    await repo.upload(saved.id);

    expect(api.createCalls, 2);
    expect(repo.recordings.single.status, ProcessingStatus.transcribing);
    expect(repo.recordings.single.remoteTaskId, 'remote-to');
  });

  test('load recovers interrupted uploading so the user can retry', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_ir_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final String path = '${dir.path}${Platform.pathSeparator}clip.m4a';
    await File(path).writeAsBytes(const <int>[1, 2, 3]);
    final DateTime now = DateTime(2026, 9, 17, 17, 20);
    final _MemoryStore store = _MemoryStore();
    await store.insert(
      Recording(
        id: 'rec-stuck',
        name: '录音 2026-09-17 17:20',
        fileName: 'clip.m4a',
        localPath: path,
        durationMs: 1000,
        createdAt: now,
        updatedAt: now,
        status: ProcessingStatus.uploading,
      ),
    );
    final RecordingRepository repo = RecordingRepository(
      database: store,
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
    );
    addTearDown(repo.dispose);

    await repo.load();

    expect(repo.recordings.single.status, ProcessingStatus.failed);
    expect(repo.recordings.single.failedStage, 'upload');
    expect((await store.findById('rec-stuck'))?.status, ProcessingStatus.failed);
    expect(
      canUploadRecording(
        repo.recordings.single.status,
        failedStage: repo.recordings.single.failedStage,
      ),
      isTrue,
    );
  });

  test('uploading or transcribing recordings cannot be deleted', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_del_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final RecordingRepository repo = RecordingRepository(
      database: _MemoryStore(),
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
    );
    addTearDown(repo.dispose);
    final Recording saved = await _persistSample(repo, dir);
    await repo.applyRemote(
      saved.id,
      const RemoteTranscription(id: 'remote-4', status: 'summarizing'),
    );

    await expectLater(
      repo.delete(saved.id),
      throwsA(
        isA<AppError>().having(
          (AppError error) => error.code,
          'code',
          'DELETE_BLOCKED',
        ),
      ),
    );
    expect(repo.recordings, hasLength(1));
    expect(await File(saved.localPath).exists(), isTrue);
  });

  test('saving another recording does not reset an in-flight upload', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_race_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final Completer<RemoteTranscription> gate = Completer<RemoteTranscription>();
    final _FakeApi api = _FakeApi(onCreate: () => gate.future);
    final RecordingRepository repo = RecordingRepository(
      database: _MemoryStore(),
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
      api: api,
    );
    addTearDown(repo.dispose);
    final Recording first = await _persistSample(repo, dir);

    final Future<void> uploading = repo.upload(first.id);
    bool sawUploading = false;
    for (int i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
      if (repo.recordings.any(
        (Recording item) =>
            item.id == first.id && item.status == ProcessingStatus.uploading,
      )) {
        sawUploading = true;
        break;
      }
    }
    expect(sawUploading, isTrue);

    await _persistSample(repo, dir);

    expect(
      repo.recordings.firstWhere((Recording item) => item.id == first.id).status,
      ProcessingStatus.uploading,
    );
    expect(
      repo.recordings
          .firstWhere((Recording item) => item.id == first.id)
          .failedStage,
      isNull,
    );

    gate.complete(
      const RemoteTranscription(id: 'remote-race', status: 'queued'),
    );
    await uploading;
    expect(
      repo.recordings.firstWhere((Recording item) => item.id == first.id).status,
      ProcessingStatus.transcribing,
    );
  });

  test('unexpected upload errors leave a retryable failed state', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_obj_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final _FakeApi api = _FakeApi(
      onCreate: () async {
        throw StateError('bad json');
      },
    );
    final RecordingRepository repo = RecordingRepository(
      database: _MemoryStore(),
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
      api: api,
    );
    addTearDown(repo.dispose);
    final Recording saved = await _persistSample(repo, dir);

    await expectLater(repo.upload(saved.id), throwsA(isA<AppError>()));
    expect(repo.recordings.single.status, ProcessingStatus.failed);
    expect(repo.recordings.single.failedStage, 'upload');
    expect(repo.recordings.single.errorCode, 'UPLOAD_FAILED');
    expect(
      canUploadRecording(
        repo.recordings.single.status,
        failedStage: repo.recordings.single.failedStage,
      ),
      isTrue,
    );
  });

  test('rename updates display name and keeps the audio file name', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_rn_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final RecordingRepository repo = RecordingRepository(
      database: _MemoryStore(),
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
    );
    addTearDown(repo.dispose);
    final Recording saved = await _persistSample(repo, dir);

    await repo.rename(saved.id, '  周会纪要  ');

    expect(repo.recordings.single.name, '周会纪要');
    expect(repo.recordings.single.fileName, saved.fileName);
    expect(repo.recordings.single.localPath, saved.localPath);
    await expectLater(repo.rename(saved.id, '   '), throwsA(isA<AppError>()));
  });
}
