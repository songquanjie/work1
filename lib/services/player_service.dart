import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../core/errors/app_error.dart';
import 'playback_policy.dart';

abstract class RecordingPlayback {
  Future<void> stopIfPlaying(String id);
}

/// 同一时刻只播一条。删除前必须先 stopIfPlaying，避免文件被占用删不掉。
class PlayerService extends ChangeNotifier implements RecordingPlayback {
  PlayerService({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _stateSub = _player.playerStateStream.listen(_onPlayerState);
    _durationSub = _player.durationStream.listen((Duration? value) {
      if (value == null || value <= Duration.zero) {
        return;
      }
      duration = value;
      _emit();
    });
    _positionSub = _player
        .createPositionStream(
          minPeriod: const Duration(milliseconds: 200),
          maxPeriod: const Duration(milliseconds: 250),
        )
        .listen((Duration value) {
      if (status == PlaybackStatus.completed) {
        return;
      }
      position = value;
      _emit();
    });
  }

  final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;

  /// 每次新的播放动作加一，用来作废还在 await play() 的旧调用。
  int _generation = 0;
  bool _suppressCompleted = false;
  bool _disposed = false;

  String? playingId;
  String? _sourcePath;
  PlaybackStatus status = PlaybackStatus.idle;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  bool isCurrent(String id) => playingId == id;

  Future<void> toggle({
    required String id,
    required String path,
  }) async {
    final PlaybackAction action = PlaybackPolicy.primaryAction(
      isCurrent: isCurrent(id),
      status: status,
    );
    switch (action) {
      case PlaybackAction.pause:
        await pause();
      case PlaybackAction.resume:
        await resume();
      case PlaybackAction.replay:
        await replay(id: id, path: path);
      case PlaybackAction.start:
        await play(id: id, path: path);
    }
  }

  Future<void> play({
    required String id,
    required String path,
  }) async {
    if (isCurrent(id) && status == PlaybackStatus.playing) {
      return;
    }
    if (isCurrent(id) && status == PlaybackStatus.paused) {
      await resume();
      return;
    }
    if (isCurrent(id) && status == PlaybackStatus.completed) {
      await replay(id: id, path: path);
      return;
    }
    await _startNew(id: id, path: path);
  }

  Future<void> pauseCurrent() async {
    if (!PlaybackPolicy.canPause(status)) {
      return;
    }
    await pause();
  }

  Future<void> pause() async {
    _generation++;
    if (playingId == null) {
      return;
    }
    await _player.pause();
    if (status == PlaybackStatus.completed) {
      return;
    }
    status = PlaybackStatus.paused;
    _emit();
  }

  Future<void> resume() async {
    if (playingId == null) {
      return;
    }
    if (status == PlaybackStatus.completed) {
      final String? id = playingId;
      final String? path = _sourcePath;
      if (id == null || path == null) {
        return;
      }
      await replay(id: id, path: path);
      return;
    }
    if (!PlaybackPolicy.canResume(status)) {
      return;
    }
    final int generation = ++_generation;
    status = PlaybackStatus.playing;
    _emit();
    unawaited(_playUntilInterrupted(generation));
  }

  Future<void> replay({
    required String id,
    required String path,
  }) async {
    await _ensureFile(path);
    final int generation = ++_generation;
    _suppressCompleted = true;
    try {
      if (!isCurrent(id)) {
        await _load(id: id, path: path);
      } else {
        await _player.seek(Duration.zero);
        position = Duration.zero;
      }
    } finally {
      _suppressCompleted = false;
    }
    if (generation != _generation) {
      if (playingId != null && status != PlaybackStatus.completed) {
        status = PlaybackStatus.paused;
        _emit();
      }
      return;
    }
    status = PlaybackStatus.playing;
    _emit();
    unawaited(_playUntilInterrupted(generation));
  }

  Future<void> seek(Duration value) async {
    if (playingId == null) {
      return;
    }
    Duration target = value;
    if (target < Duration.zero) {
      target = Duration.zero;
    }
    if (duration > Duration.zero && target > duration) {
      target = duration;
    }
    _suppressCompleted = true;
    try {
      await _player.seek(target);
    } finally {
      _suppressCompleted = false;
    }
    position = target;
    if (status == PlaybackStatus.completed && target < duration) {
      status = PlaybackStatus.paused;
    }
    _emit();
  }

  @override
  Future<void> stopIfPlaying(String id) async {
    if (playingId != id) {
      return;
    }
    _generation++;
    _suppressCompleted = true;
    try {
      await _player.stop();
      playingId = null;
      _sourcePath = null;
      status = PlaybackStatus.idle;
      position = Duration.zero;
      duration = Duration.zero;
      _emit();
    } finally {
      _suppressCompleted = false;
    }
  }

  Future<void> _startNew({required String id, required String path}) async {
    await _ensureFile(path);
    final int generation = ++_generation;
    await _load(id: id, path: path);
    if (generation != _generation) {
      if (playingId != null) {
        status = PlaybackStatus.paused;
        _emit();
      }
      return;
    }
    status = PlaybackStatus.playing;
    _emit();
    unawaited(_playUntilInterrupted(generation));
  }

  /// just_audio's [AudioPlayer.play] completes when playback ends, pauses, or
  /// stops. Never await it inside a mutex, or pause/replay cannot run.
  Future<void> _playUntilInterrupted(int generation) async {
    try {
      await _player.play();
    } catch (_) {
      if (generation != _generation || playingId == null) {
        return;
      }
      if (status == PlaybackStatus.playing) {
        status = PlaybackStatus.paused;
        _emit();
      }
    }
  }

  Future<void> _load({required String id, required String path}) async {
    _suppressCompleted = true;
    try {
      await _player.stop();
      final Duration? loaded = await _player.setFilePath(path);
      playingId = id;
      _sourcePath = path;
      position = Duration.zero;
      duration = loaded ?? Duration.zero;
    } finally {
      _suppressCompleted = false;
    }
  }

  Future<void> _ensureFile(String path) async {
    final File file = File(path);
    if (!await file.exists()) {
      throw const AppError(
        code: 'FILE_MISSING',
        message: '录音文件不存在或已损坏，无法播放。',
      );
    }
  }

  void _onPlayerState(PlayerState state) {
    if (_disposed || _suppressCompleted || playingId == null) {
      return;
    }
    if (state.processingState == ProcessingState.completed) {
      status = PlaybackStatus.completed;
      if (duration > Duration.zero) {
        position = duration;
      }
      _emit();
      return;
    }
    // Stale playing:true frames after pause must not flip the UI back.
    if (state.playing && status == PlaybackStatus.paused) {
      return;
    }
    if (state.playing && status != PlaybackStatus.playing) {
      status = PlaybackStatus.playing;
      _emit();
    }
  }

  void _emit() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_stateSub?.cancel());
    unawaited(_durationSub?.cancel());
    unawaited(_positionSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }
}
