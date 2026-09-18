import 'package:echonote/data/local/recording_database.dart';
import 'package:echonote/features/recording_detail/recording_detail_page.dart';
import 'package:echonote/models/processing_status.dart';
import 'package:echonote/models/recording.dart';
import 'package:echonote/repositories/recording_repository.dart';
import 'package:echonote/services/player_service.dart';
import 'package:echonote/services/recording_file_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _MemoryStore implements RecordingStore {
  _MemoryStore(this.row);

  Recording row;

  @override
  Future<void> insert(Recording recording) async {
    row = recording;
  }

  @override
  Future<void> update(Recording recording) async {
    row = recording;
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Recording?> findById(String id) async => row.id == id ? row : null;

  @override
  Future<List<Recording>> findAllNewestFirst() async => <Recording>[row];

  @override
  Future<void> close() async {}
}

class _SilentPlayback implements RecordingPlayback {
  @override
  Future<void> stopIfPlaying(String id) async {}
}

Recording _sample({
  ProcessingStatus status = ProcessingStatus.pendingUpload,
  String? remoteTaskId,
  String? transcript,
  String? summary,
  String? failedStage,
  String? errorMessage,
}) {
  return Recording(
    id: 'rec-1',
    name: '录音 2026-09-17 10:00',
    fileName: 'clip.m4a',
    localPath: '/tmp/clip.m4a',
    durationMs: 8000,
    createdAt: DateTime(2026, 9, 17, 10),
    updatedAt: DateTime(2026, 9, 17, 10),
    status: status,
    remoteTaskId: remoteTaskId,
    transcript: transcript,
    summary: summary,
    failedStage: failedStage,
    errorMessage: errorMessage,
  );
}

Future<void> _pumpDetail(WidgetTester tester, Recording recording) async {
  final RecordingRepository repository = RecordingRepository(
    database: _MemoryStore(recording),
    files: RecordingFileStore(),
    playback: _SilentPlayback(),
  );
  repository.recordings = <Recording>[recording];
  final PlayerService player = PlayerService();
  addTearDown(player.dispose);
  addTearDown(repository.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<RecordingRepository>.value(
      value: repository,
      child: ChangeNotifierProvider<PlayerService>.value(
        value: player,
        child: MaterialApp(
          home: RecordingDetailPage(recordingId: recording.id),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('pending upload shows upload action', (WidgetTester tester) async {
    await _pumpDetail(tester, _sample());
    expect(find.text('待上传'), findsOneWidget);
    expect(find.text('上传并转写'), findsOneWidget);
    expect(find.text('转写全文'), findsNothing);
  });

  testWidgets('failed summary keeps transcript and offers remote retry', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(
      tester,
      _sample(
        status: ProcessingStatus.failed,
        remoteTaskId: 'remote-1',
        transcript: '会议全文',
        failedStage: 'summarizing',
        errorMessage: '未配置摘要服务',
      ),
    );
    expect(find.text('处理失败'), findsOneWidget);
    expect(find.text('未配置摘要服务'), findsOneWidget);
    expect(find.text('会议全文'), findsOneWidget);
    expect(find.text('重新生成摘要'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
  });

  testWidgets('completed result can copy transcript and summary', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(
      tester,
      _sample(
        status: ProcessingStatus.completed,
        remoteTaskId: 'remote-1',
        transcript: '会议全文',
        summary: '三点结论',
      ),
    );
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('转写全文'), findsOneWidget);
    expect(find.text('智能摘要'), findsOneWidget);
    expect(find.text('复制'), findsNWidgets(2));
  });

  testWidgets('detail page can play and rename', (WidgetTester tester) async {
    await _pumpDetail(tester, _sample());
    expect(find.byTooltip('播放'), findsOneWidget);
    expect(find.byTooltip('重新播放'), findsOneWidget);
    expect(find.byTooltip('重命名'), findsOneWidget);
    expect(find.byKey(const Key('detail_playback_progress')), findsOneWidget);
  });
}
