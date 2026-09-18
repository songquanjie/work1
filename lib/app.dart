import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/ble/ble_controller.dart';
import 'features/recorder/recorder_controller.dart';
import 'repositories/recording_repository.dart';
import 'services/player_service.dart';

/// 注入仓库/播放器，并按前后台启停轮询。
///
/// 必须包在 [MaterialApp] **外面**。不要放进 `MaterialApp.builder`，
/// 否则详情路由、重命名弹窗弹出时会把 InheritedWidget 拆坏。
/// 传入的服务由创建方 dispose。这里只停轮询、移除前后台观察者。
class EchoNoteApp extends StatefulWidget {
  const EchoNoteApp({
    super.key,
    required this.repository,
    required this.player,
    required this.recorderController,
    required this.bleController,
    required this.child,
    this.pollingEnabled = true,
  });

  final RecordingRepository repository;
  final PlayerService player;
  final RecorderController recorderController;
  final BleController bleController;
  final Widget child;
  final bool pollingEnabled;

  @override
  State<EchoNoteApp> createState() => _EchoNoteAppState();
}

class _EchoNoteAppState extends State<EchoNoteApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.pollingEnabled) {
      _startPolling();
    }
  }

  @override
  void didUpdateWidget(covariant EchoNoteApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pollingEnabled && !oldWidget.pollingEnabled) {
      _startPolling();
    }
  }

  void _startPolling() {
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
      unawaited(widget.bleController.stopScan());
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
    widget.repository.poller?.stop();
    WidgetsBinding.instance.removeObserver(this);
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
        ChangeNotifierProvider<BleController>.value(
          value: widget.bleController,
        ),
      ],
      child: widget.child,
    );
  }
}
