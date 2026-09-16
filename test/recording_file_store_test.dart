import 'dart:io';

import 'package:echonote/core/errors/app_error.dart';
import 'package:echonote/services/recording_file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('persistStoppedFile keeps the real extension', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final String tempPath = p.join(dir.path, 'tmp_1.aac');
    await File(tempPath).writeAsBytes(const <int>[1, 2, 3]);

    final SavedRecording saved = await RecordingFileStore().persistStoppedFile(
      tempPath: tempPath,
      durationMs: 1200,
    );

    expect(p.extension(saved.path), '.aac');
    expect(await File(saved.path).exists(), isTrue);
    expect(await File(tempPath).exists(), isFalse);
    expect(saved.durationMs, 1200);
  });

  test('persistStoppedFile rejects an empty encoder output', () async {
    final Directory dir = await Directory.systemTemp.createTemp('echonote_empty_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final String tempPath = p.join(dir.path, 'tmp_1.m4a');
    await File(tempPath).create();

    await expectLater(
      RecordingFileStore().persistStoppedFile(
        tempPath: tempPath,
        durationMs: 0,
      ),
      throwsA(isA<AppError>()),
    );
  });
}
