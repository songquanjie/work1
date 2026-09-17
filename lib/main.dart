import 'package:flutter/material.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'data/local/recording_database.dart';
import 'data/remote/transcription_api.dart';
import 'features/recorder/recorder_controller.dart';
import 'repositories/recording_repository.dart';
import 'services/player_service.dart';
import 'services/recorder_service.dart';
import 'services/recording_file_store.dart';

/// 先打开数据库再进首页，这样列表第一帧就能看到杀进程前的录音。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final RecordingDatabase database = RecordingDatabase();
  await database.init();
  final PlayerService player = PlayerService();
  final RecordingRepository repository = RecordingRepository(
    database: database,
    files: RecordingFileStore(),
    playback: player,
    api: TranscriptionApi(baseUrl: AppConfig.apiBaseUrl),
  );
  await repository.load();
  runApp(
    EchoNoteApp(
      repository: repository,
      player: player,
      recorderController: RecorderController(
        recorder: RecorderService(),
        repository: repository,
      ),
    ),
  );
}
