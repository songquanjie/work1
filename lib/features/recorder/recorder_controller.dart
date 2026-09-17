import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/errors/app_error.dart';
import '../../core/utils/time_format.dart';
import '../../repositories/recording_repository.dart';
import '../../services/recorder_service.dart';
import 'recorder_state.dart';

/// 录音页用例：权限、开始/暂停/继续/停止。不直接写 SQLite。
class RecorderController extends ChangeNotifier with WidgetsBindingObserver {
  RecorderController({
    required RecorderService recorder,
    required RecordingRepository repository,
  })  : _recorder = recorder,
        _repository = repository {
    WidgetsBinding.instance.addObserver(this);
  }

  final RecorderService _recorder;
  final RecordingRepository _repository;

  RecorderState state = RecorderState.idle;
  Duration elapsed = Duration.zero;
  double volumeLevel = 0;
  String? errorMessage;
  bool permanentlyDenied = false;
  bool _busy = false;

  Timer? _ticker;
  DateTime? _startedAt;
  Duration _accumulated = Duration.zero;
  StreamSubscription<double>? _ampSub;

  /// 异步录音调用进行中。用来防连点开出两段录音，不是时间防抖。
  bool get busy => _busy || RecorderUiPolicy.buttonsLocked(state);

  Future<void> start() async {
    if (!RecorderUiPolicy.canStart(state) || busy) {
      return;
    }
    await _runExclusive(() async {
      errorMessage = null;
      permanentlyDenied = false;
      final MicPermissionResult permission = await _recorder.ensurePermission();
      if (permission == MicPermissionResult.denied) {
        errorMessage = '需要麦克风权限才能录音。';
        return;
      }
      if (permission == MicPermissionResult.permanentlyDenied) {
        permanentlyDenied = true;
        errorMessage = '麦克风权限已被永久拒绝，请在系统设置中开启。';
        return;
      }
      try {
        await _recorder.start();
        state = RecorderState.recording;
        _accumulated = Duration.zero;
        elapsed = Duration.zero;
        _startedAt = DateTime.now();
        _startTicker();
        await _ampSub?.cancel();
        _ampSub = _recorder.amplitudeDb.listen((double db) {
          volumeLevel = amplitudeToLevel(db);
          notifyListeners();
        });
      } catch (_) {
        state = RecorderState.idle;
        errorMessage = '无法开始录音，请重试。';
      }
    });
  }

  Future<void> pause() async {
    if (!RecorderUiPolicy.canPause(state) || busy) {
      return;
    }
    await _runExclusive(() async {
      try {
        await _recorder.pause();
        _accumulate();
        state = RecorderState.paused;
        volumeLevel = 0;
        _ticker?.cancel();
      } catch (_) {
        errorMessage = '暂停失败，请重试。';
      }
    });
  }

  Future<void> resume() async {
    if (!RecorderUiPolicy.canResume(state) || busy) {
      return;
    }
    await _runExclusive(() async {
      try {
        await _recorder.resume();
        state = RecorderState.recording;
        _startedAt = DateTime.now();
        _startTicker();
      } catch (_) {
        errorMessage = '继续录音失败，请重试。';
      }
    });
  }

  Future<void> stop() async {
    if (!RecorderUiPolicy.canStop(state) || busy) {
      return;
    }
    await _runExclusive(() async {
      state = RecorderState.saving;
      notifyListeners();
      _ticker?.cancel();
      _accumulate();
      try {
        final String? path = await _recorder.stop();
        if (path == null || path.isEmpty) {
          throw const AppError(code: 'SAVE_FAILED', message: '保存失败：未生成音频文件。');
        }
        await _repository.persistStoppedFile(
          tempPath: path,
          durationMs: elapsed.inMilliseconds,
        );
        state = RecorderState.idle;
        volumeLevel = 0;
        errorMessage = null;
      } on AppError catch (error) {
        state = RecorderState.saveFailed;
        errorMessage = error.message;
      } catch (_) {
        state = RecorderState.saveFailed;
        errorMessage = '保存失败，请重新录制。';
      }
    });
  }

  Future<void> openSettings() => _recorder.openSettings();

  Future<void> _runExclusive(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (state != RecorderState.recording || _startedAt == null) {
        return;
      }
      elapsed = _accumulated + DateTime.now().difference(_startedAt!);
      notifyListeners();
    });
  }

  void _accumulate() {
    if (_startedAt != null) {
      _accumulated += DateTime.now().difference(_startedAt!);
      elapsed = _accumulated;
      _startedAt = null;
    }
  }

  /// P0 不做后台持续录音。permission 弹窗也会发 inactive，所以只处理 paused/hidden。
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.paused &&
        lifecycle != AppLifecycleState.hidden) {
      return;
    }
    if (state == RecorderState.recording || state == RecorderState.paused) {
      unawaited(stop());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_ampSub?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
