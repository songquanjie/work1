import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/recorder/recorder_controller.dart';
import 'features/recording_list/recording_list_page.dart';
import 'repositories/recording_repository.dart';
import 'services/player_service.dart';

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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(widget.player.pauseCurrent());
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
