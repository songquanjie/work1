import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/recorder/recorder_controller.dart';
import 'features/recording_list/recording_list_page.dart';
import 'repositories/recording_repository.dart';
import 'services/player_service.dart';

/// 根组件：注入仓库/播放器，并按前后台启停轮询。
class EchoNoteApp extends StatefulWidget {
  const EchoNoteApp({
    super.key,
    required this.repository,
    required this.player,
    required this.recorderController,
  });

  final RecordingRepository repository;
  final PlayerService player;
  final RecorderController recorderController;

  @override
  State<EchoNoteApp> createState() => _EchoNoteAppState();
}

class _EchoNoteAppState extends State<EchoNoteApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 前台才轮询，避免后台一直打转写查询。
    widget.repository.poller?.start();
    final Future<void>? firstRefresh = widget.repository.poller?.refresh();
    if (firstRefresh != null) {
      unawaited(firstRefresh);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(widget.player.pauseCurrent());
      widget.repository.poller?.stop();
    } else if (state == AppLifecycleState.resumed) {
      widget.repository.poller?.start();
      final Future<void>? refresh = widget.repository.poller?.refresh();
      if (refresh != null) {
        unawaited(refresh);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.recorderController.dispose();
    widget.player.dispose();
    widget.repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RecordingRepository>.value(
          value: widget.repository,
        ),
        ChangeNotifierProvider<PlayerService>.value(value: widget.player),
        ChangeNotifierProvider<RecorderController>.value(
          value: widget.recorderController,
        ),
      ],
      child: MaterialApp(
        title: '随身录音笔记',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
          useMaterial3: true,
        ),
        home: const RecordingListPage(),
      ),
    );
  }
}
