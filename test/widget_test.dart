import 'package:echonote/app.dart';
import 'package:echonote/data/local/recording_database.dart';
import 'package:echonote/features/launch/echo_note_launch_page.dart';
import 'package:echonote/features/recorder/recorder_controller.dart';
import 'package:echonote/features/recording_detail/recording_detail_page.dart';
import 'package:echonote/features/recording_list/recording_list_page.dart';
import 'package:echonote/models/recording.dart';
import 'package:echonote/repositories/recording_repository.dart';
import 'package:echonote/services/player_service.dart';
import 'package:echonote/services/recorder_service.dart';
import 'package:echonote/services/recording_file_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _MemoryStore implements RecordingStore {
  @override
  Future<void> insert(Recording recording) async {}

  @override
  Future<void> update(Recording recording) async {}

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

Recording _sampleRecording() {
  return Recording(
    id: 'rec-1',
    name: '周会',
    fileName: 'clip.m4a',
    localPath: '/tmp/clip.m4a',
    durationMs: 8000,
    createdAt: DateTime(2026, 9, 17, 10),
    updatedAt: DateTime(2026, 9, 17, 10),
  );
}

Widget _appTree({
  required RecordingRepository repository,
  required PlayerService player,
  required RecorderController recorder,
  required Widget home,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  return EchoNoteApp(
    repository: repository,
    player: player,
    recorderController: recorder,
    child: MaterialApp(
      navigatorKey: navigatorKey,
      home: home,
    ),
  );
}

(RecordingRepository, PlayerService, RecorderController) _services() {
  final RecordingRepository repository = RecordingRepository(
    database: _MemoryStore(),
    files: RecordingFileStore(),
    playback: _SilentPlayback(),
  );
  final PlayerService player = PlayerService();
  final RecorderController recorder = RecorderController(
    recorder: RecorderService(),
    repository: repository,
  );
  addTearDown(repository.dispose);
  addTearDown(player.dispose);
  addTearDown(recorder.dispose);
  return (repository, player, recorder);
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

  testWidgets('launch page is a blank white screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: EchoNoteLaunchPage()),
    );
    expect(find.byKey(const Key('launch_blank')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('launch page can retry after boot failure', (
    WidgetTester tester,
  ) async {
    bool retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: EchoNoteLaunchPage(
          errorMessage: '启动失败，请重试。',
          onRetry: () => retried = true,
        ),
      ),
    );
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retried, isTrue);
  });

  testWidgets('ready app sits under a single MaterialApp', (
    WidgetTester tester,
  ) async {
    final (RecordingRepository repository, PlayerService player,
            RecorderController recorder) =
        _services();

    await tester.pumpWidget(
      _appTree(
        repository: repository,
        player: player,
        recorder: recorder,
        home: const RecordingListPage(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(RecordingListPage), findsOneWidget);
  });

  testWidgets('pushed detail page can read RecordingRepository', (
    WidgetTester tester,
  ) async {
    final (RecordingRepository repository, PlayerService player,
            RecorderController recorder) =
        _services();
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      _appTree(
        repository: repository,
        player: player,
        recorder: recorder,
        navigatorKey: navigatorKey,
        home: const RecordingListPage(),
      ),
    );

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const RecordingDetailPage(recordingId: 'missing'),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('这条录音已删除'), findsOneWidget);
  });

  testWidgets('rename dialog opens from detail without inherited crash', (
    WidgetTester tester,
  ) async {
    final (RecordingRepository repository, PlayerService player,
            RecorderController recorder) =
        _services();
    final Recording recording = _sampleRecording();
    repository.recordings = <Recording>[recording];

    await tester.pumpWidget(
      _appTree(
        repository: repository,
        player: player,
        recorder: recorder,
        home: RecordingDetailPage(recordingId: recording.id),
      ),
    );

    await tester.tap(find.byTooltip('重命名'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('重命名'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '周会纪要');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('周会纪要'), findsOneWidget);
    expect(repository.recordings.single.name, '周会纪要');
    expect(repository.recordings.single.fileName, 'clip.m4a');
  });
}
