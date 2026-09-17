import 'package:echonote/features/recording_list/recording_list_page.dart';
import 'package:echonote/models/processing_status.dart';
import 'package:echonote/models/recording.dart';
import 'package:echonote/services/playback_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final Recording sample = Recording(
    id: 'rec-1',
    name: '录音 2026-09-16 14:30',
    fileName: 'recording_1.m4a',
    localPath: '/tmp/recording_1.m4a',
    durationMs: 125000,
    createdAt: DateTime(2026, 9, 16, 14, 30),
    updatedAt: DateTime(2026, 9, 16, 14, 30),
  );

  Widget tile({
    bool isCurrent = false,
    PlaybackStatus status = PlaybackStatus.idle,
    bool missing = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: RecordingListTile(
          recording: missing ? sample.copyWith(fileMissing: true) : sample,
          isCurrent: isCurrent,
          status: status,
          position: Duration.zero,
          duration: Duration(milliseconds: sample.durationMs),
          onPlayPause: () {},
          onReplay: () {},
          onSeek: (_) {},
          onDelete: () {},
        ),
      ),
    );
  }

  testWidgets('tile shows name, duration, play and delete', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(tile());
    expect(find.text('录音 2026-09-16 14:30'), findsOneWidget);
    expect(find.textContaining('02:05'), findsOneWidget);
    expect(find.textContaining('待上传'), findsOneWidget);
    expect(find.text('上传'), findsNothing);
    expect(find.byTooltip('播放'), findsOneWidget);
    expect(find.byTooltip('重新播放'), findsOneWidget);
    expect(find.byTooltip('删除'), findsOneWidget);
    expect(find.byKey(const Key('playback_progress')), findsNothing);
  });

  testWidgets('current playing row shows pause and progress', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      tile(isCurrent: true, status: PlaybackStatus.playing),
    );
    expect(find.byTooltip('暂停'), findsOneWidget);
    expect(find.byKey(const Key('playback_progress')), findsOneWidget);
  });

  testWidgets('completed current row offers replay as primary action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      tile(isCurrent: true, status: PlaybackStatus.completed),
    );
    expect(find.byTooltip('重新播放'), findsWidgets);
  });

  testWidgets('missing file disables play', (WidgetTester tester) async {
    await tester.pumpWidget(tile(missing: true));
    final IconButton play = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.play_arrow).first,
    );
    expect(play.onPressed, isNull);
    expect(find.textContaining('文件缺失'), findsOneWidget);
  });

  testWidgets('pending upload row can show upload action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordingListTile(
            recording: sample,
            isCurrent: false,
            status: PlaybackStatus.idle,
            position: Duration.zero,
            duration: Duration(milliseconds: sample.durationMs),
            onPlayPause: () {},
            onReplay: () {},
            onSeek: (_) {},
            onDelete: () {},
            onUpload: () {},
          ),
        ),
      ),
    );
    expect(find.byTooltip('上传'), findsOneWidget);
  });

  testWidgets('processing row disables delete', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordingListTile(
            recording: sample.copyWith(status: ProcessingStatus.transcribing),
            isCurrent: false,
            status: PlaybackStatus.idle,
            position: Duration.zero,
            duration: Duration(milliseconds: sample.durationMs),
            onPlayPause: () {},
            onReplay: () {},
            onSeek: (_) {},
          ),
        ),
      ),
    );
    final IconButton delete = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );
    expect(delete.onPressed, isNull);
    expect(find.textContaining('转写处理中'), findsOneWidget);
  });

  testWidgets('upload row fits a narrow phone width', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordingListTile(
            recording: sample,
            isCurrent: false,
            status: PlaybackStatus.idle,
            position: Duration.zero,
            duration: Duration(milliseconds: sample.durationMs),
            onPlayPause: () {},
            onReplay: () {},
            onSeek: (_) {},
            onDelete: () {},
            onUpload: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('上传'), findsOneWidget);
  });
}
