import 'package:echonote/core/utils/time_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatClock pads minutes and seconds', () {
    expect(formatClock(Duration.zero), '00:00');
    expect(formatClock(const Duration(minutes: 3, seconds: 25)), '03:25');
    expect(
      formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '01:02:03',
    );
  });

  test('amplitudeToLevel clamps the visible meter', () {
    expect(amplitudeToLevel(-90), 0);
    expect(amplitudeToLevel(0), 1);
    expect(amplitudeToLevel(-22.5) > 0.4, isTrue);
  });

  test('formatDurationMs never goes negative', () {
    expect(formatDurationMs(-12), '00:00');
    expect(formatDurationMs(125000), '02:05');
    expect(formatDurationMs(400), '00:01');
  });

  test('formatRecordingName uses a stable local label', () {
    final DateTime time = DateTime(2026, 9, 16, 14, 30);
    expect(formatRecordingName(time), '录音 2026-09-16 14:30');
    expect(formatCreatedAt(time), '2026-09-16 14:30');
  });
}
