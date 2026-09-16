import 'package:flutter/material.dart';

import 'app.dart';
import 'data/local/recording_database.dart';
import 'features/recorder/recorder_controller.dart';
import 'repositories/recording_repository.dart';
import 'services/player_service.dart';
import 'services/recorder_service.dart';
import 'services/recording_file_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final RecordingDatabase database = RecordingDatabase();
  await database.init();
  final PlayerService player = PlayerService();
  final RecordingRepository repository = RecordingRepository(
    database: database,
    files: RecordingFileStore(),
    playback: player,
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
