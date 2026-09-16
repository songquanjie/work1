import 'dart:io';

import 'package:echonote/core/errors/app_error.dart';
import 'package:echonote/data/local/recording_database.dart';
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
}
