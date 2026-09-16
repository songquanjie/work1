import 'package:echonote/data/local/recording_database.dart';
import 'package:echonote/features/recording_list/recording_list_page.dart';
import 'package:echonote/models/recording.dart';
import 'package:echonote/repositories/recording_repository.dart';
import 'package:echonote/services/player_service.dart';
import 'package:echonote/services/recording_file_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _MemoryStore implements RecordingStore {
  @override
  Future<void> insert(Recording recording) async {}

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
  @override
  Future<void> stopIfPlaying(String id) async {}
}

void main() {
  testWidgets('home shows empty list and create action', (
    WidgetTester tester,
  ) async {
    final RecordingRepository repository = RecordingRepository(
      database: _MemoryStore(),
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
    );
    final PlayerService player = PlayerService();
    addTearDown(player.dispose);
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<RecordingRepository>.value(
        value: repository,
        child: ChangeNotifierProvider<PlayerService>.value(
          value: player,
          child: const MaterialApp(home: RecordingListPage()),
        ),
      ),
    );

    expect(find.text('随身录音笔记'), findsOneWidget);
    expect(find.text('还没有录音，点右下角开始一条'), findsOneWidget);
    expect(find.text('新建录音'), findsOneWidget);
  });
}
