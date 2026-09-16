import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../core/errors/app_error.dart';

enum MicPermissionResult { granted, denied, permanentlyDenied }

/// Microphone capture only. Persistence and UI live elsewhere.
class RecorderService {
  RecorderService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  StreamSubscription<Amplitude>? _amplitudeSub;

  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  Stream<double> get amplitudeDb => _amplitudeController.stream;

  Future<MicPermissionResult> ensurePermission() async {
    PermissionStatus status = await Permission.microphone.status;
    if (status.isGranted) {
      return MicPermissionResult.granted;
    }
    if (status.isPermanentlyDenied) {
      return MicPermissionResult.permanentlyDenied;
    }
    status = await Permission.microphone.request();
    if (status.isGranted) {
      return MicPermissionResult.granted;
    }
    if (status.isPermanentlyDenied) {
      return MicPermissionResult.permanentlyDenied;
    }
    return MicPermissionResult.denied;
  }

  Future<bool> openSettings() => openAppSettings();

  Future<String> start() async {
    final bool available = await _recorder.hasPermission();
    if (!available) {
      throw const AppError(
        code: 'MIC_PERMISSION',
        message: '没有麦克风权限，无法开始录音。',
      );
    }
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory recDir = Directory(p.join(docs.path, 'recordings'));
    if (!await recDir.exists()) {
      await recDir.create(recursive: true);
    }
    // aacLc typically lands as .m4a; stop() returns the real path and wins.
    final String tempPath = p.join(
      recDir.path,
      'tmp_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: tempPath,
    );
    await _amplitudeSub?.cancel();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((Amplitude amplitude) {
      if (!_amplitudeController.isClosed) {
        _amplitudeController.add(amplitude.current);
      }
    });
    return tempPath;
  }

  Future<void> pause() => _recorder.pause();

  Future<void> resume() => _recorder.resume();

  Future<String?> stop() async {
    final String? path = await _recorder.stop();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    return path;
  }

  Future<void> dispose() async {
    await _amplitudeSub?.cancel();
    await _amplitudeController.close();
    await _recorder.dispose();
  }
}
