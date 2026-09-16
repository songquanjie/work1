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
    );
    final Recording restored = Recording.fromMap(original.toMap());
    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.fileName, original.fileName);
    expect(restored.localPath, original.localPath);
    expect(restored.durationMs, original.durationMs);
    expect(restored.createdAt, original.createdAt);
    expect(restored.canPlay, isTrue);
  });
}
