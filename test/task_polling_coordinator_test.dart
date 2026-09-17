import 'package:echonote/models/processing_status.dart';
import 'package:echonote/models/recording.dart';
import 'package:echonote/services/task_polling_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coordinator does not start overlapping ticks', () async {
    int calls = 0;
    final List<Recording> items = <Recording>[
      Recording(
        id: 'a',
        name: '录音',
        fileName: 'a.m4a',
        localPath: '/a.m4a',
        durationMs: 1000,
        createdAt: DateTime(2026, 9, 17),
        updatedAt: DateTime(2026, 9, 17),
        status: ProcessingStatus.transcribing,
        remoteTaskId: 'remote-1',
      ),
    ];
    final TaskPollingCoordinator coordinator = TaskPollingCoordinator(
      lookup: () => items,
      sync: (Recording item) async {
        calls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 40));
      },
    );

    final Future<void> first = coordinator.refresh();
    final Future<void> second = coordinator.refresh();
    await Future.wait(<Future<void>>[first, second]);
    expect(calls, 1);
  });
}
