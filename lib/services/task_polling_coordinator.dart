import 'dart:async';

import '../models/processing_status.dart';
import '../models/recording.dart';

typedef TranscribingLookup = List<Recording> Function();
typedef SyncRemote = Future<void> Function(Recording item);

/// 前台每 5 秒拉一次「转写中」任务。后台停表，避免 App 被杀掉后还打接口。
class TaskPollingCoordinator {
  TaskPollingCoordinator({
    required TranscribingLookup lookup,
    required SyncRemote sync,
    this.interval = const Duration(seconds: 5),
  })  : _lookup = lookup,
        _sync = sync;

  final TranscribingLookup _lookup;
  final SyncRemote _sync;
  final Duration interval;

  Timer? _timer;
  bool _tickRunning = false;

  bool get isRunning => _timer != null;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(refresh()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 上一轮未完成时直接跳过，避免 5s 锁被拉长成并发 GET。
  Future<void> refresh() async {
    if (_tickRunning) {
      return;
    }
    _tickRunning = true;
    try {
      final List<Recording> active = _lookup()
          .where(
            (Recording item) =>
                item.status == ProcessingStatus.transcribing &&
                (item.remoteTaskId ?? '').isNotEmpty,
          )
          .toList();
      for (final Recording item in active) {
        await _sync(item);
      }
    } finally {
      _tickRunning = false;
    }
  }

  void dispose() {
    stop();
  }
}
