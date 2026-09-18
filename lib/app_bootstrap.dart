import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'data/local/recording_database.dart';
import 'data/remote/transcription_api.dart';
import 'features/ble/ble_controller.dart';
import 'features/home/home_shell.dart';
import 'features/launch/echo_note_launch_page.dart';
import 'features/recorder/recorder_controller.dart';
import 'repositories/recording_repository.dart';
import 'services/flutter_blue_plus_ble_scanner.dart';
import 'services/player_service.dart';
import 'services/recorder_service.dart';
import 'services/recording_file_store.dart';

/// 先画出白屏再打开数据库。
///
/// 第一帧起就是 `Provider -> MaterialApp`，只换 home，不换根组件，也不用
/// `MaterialApp.builder` 塞 Provider（弹窗/新路由会红屏）。
/// 仓库/播放器由这里创建和销毁，[EchoNoteApp] 只负责注入和前后台轮询。
class EchoNoteBootstrap extends StatefulWidget {
  const EchoNoteBootstrap({super.key});

  @override
  State<EchoNoteBootstrap> createState() => _EchoNoteBootstrapState();
}

class _EchoNoteBootstrapState extends State<EchoNoteBootstrap> {
  late final RecordingDatabase _database;
  late final PlayerService _player;
  late final RecordingRepository _repository;
  late final RecorderController _recorder;
  late final BleController _ble;
  bool _ready = false;
  bool _booting = false;
  bool _disposed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = PlayerService();
    _database = RecordingDatabase();
    _repository = RecordingRepository(
      database: _database,
      files: RecordingFileStore(),
      playback: _player,
      api: TranscriptionApi(baseUrl: AppConfig.apiBaseUrl),
    );
    _recorder = RecorderController(
      recorder: RecorderService(),
      repository: _repository,
    );
    _ble = BleController(scanner: FlutterBluePlusBleScanner());
    unawaited(_boot());
  }

  Future<void> _boot() async {
    if (_booting || _disposed) {
      return;
    }
    _booting = true;
    if (mounted && _error != null) {
      setState(() {});
    }
    try {
      await _database.init();
      await _repository.load();
      if (_disposed || !mounted) {
        return;
      }
      setState(() {
        _ready = true;
        _error = null;
      });
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'echonote',
          context: ErrorDescription('打开本地数据库'),
        ),
      );
      if (_disposed || !mounted) {
        return;
      }
      setState(() {
        _error = '启动失败，请重试。';
      });
    } finally {
      _booting = false;
      if (mounted && !_ready && !_disposed) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ble.dispose();
    _recorder.dispose();
    _player.dispose();
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EchoNoteApp(
      repository: _repository,
      player: _player,
      recorderController: _recorder,
      bleController: _ble,
      pollingEnabled: _ready,
      child: MaterialApp(
        title: '随身录音笔记',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
          useMaterial3: true,
        ),
        home: _ready
            ? const HomeShell()
            : EchoNoteLaunchPage(
                errorMessage: _error,
                onRetry: _error == null ? null : () => unawaited(_boot()),
                retrying: _booting && _error != null,
              ),
      ),
    );
  }
}
