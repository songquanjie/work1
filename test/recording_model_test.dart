import 'package:echonote/models/recording.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toMap/fromMap round-trips local metadata', () {
    final Recording original = Recording(
      id: 'id-1',
      name: '录音 2026-09-16 14:30',
      fileName: 'recording_1.m4a',
      localPath: '/data/recording_1.m4a',
      durationMs: 1500,
      createdAt: DateTime(2026, 9, 16, 14, 30),
      updatedAt: DateTime(2026, 9, 16, 14, 30),
    );
    final Recording restored = Recording.fromMap(original.toMap());
    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.fileName, original.fileName);
    expect(restored.localPath, original.localPath);
    expect(restored.durationMs, original.durationMs);
    expect(restored.createdAt, original.createdAt);
    expect(restored.status, original.status);
    expect(restored.canPlay, isTrue);
  });

  test('copyWith can change display name without touching fileName', () {
    final Recording original = Recording(
      id: 'id-1',
      name: '录音 2026-09-16 14:30',
      fileName: 'recording_1.m4a',
      localPath: '/data/recording_1.m4a',
      durationMs: 1500,
      createdAt: DateTime(2026, 9, 16, 14, 30),
      updatedAt: DateTime(2026, 9, 16, 14, 30),
    );
    final Recording renamed = original.copyWith(name: '周会纪要');
    expect(renamed.name, '周会纪要');
    expect(renamed.fileName, 'recording_1.m4a');
    expect(renamed.localPath, original.localPath);
  });
}
