import 'processing_status.dart';

/// 一条本地录音。转写全文、摘要、远端任务 id 都落在这条记录上，杀进程后还能查。
class Recording {
  const Recording({
    required this.id,
    required this.name,
    required this.fileName,
    required this.localPath,
    required this.durationMs,
    required this.createdAt,
    required this.updatedAt,
    this.status = ProcessingStatus.pendingUpload,
    this.processingStage,
    this.remoteTaskId,
    this.transcript,
    this.summary,
    this.errorCode,
    this.errorMessage,
    this.failedStage,
    this.retryCount = 0,
    this.lastCheckedAt,
    this.fileMissing = false,
    this.pollStale = false,
  });

  final String id;
  final String name;
  final String fileName;
  final String localPath;
  final int durationMs;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ProcessingStatus status;
  final String? processingStage;
  final String? remoteTaskId;
  final String? transcript;
  final String? summary;
  final String? errorCode;
  final String? errorMessage;
  final String? failedStage;
  final int retryCount;
  final DateTime? lastCheckedAt;
  /// 文件是否还在磁盘上，启动时探测，不入库。
  final bool fileMissing;
  /// 仅内存：查询超时用来显示「状态暂时无法更新」，重启后清掉。
  final bool pollStale;

  bool get canPlay => !fileMissing;

  String get statusLabel {
    if (pollStale && status == ProcessingStatus.transcribing) {
      return '状态暂时无法更新';
    }
    return processingStatusLabel(status, stage: processingStage);
  }

  /// 可空字段用 [_unset] 哨兵，才能把 transcript / error 真正写成 null。
  Recording copyWith({
    DateTime? updatedAt,
    ProcessingStatus? status,
    Object? processingStage = _unset,
    Object? remoteTaskId = _unset,
    Object? transcript = _unset,
    Object? summary = _unset,
    Object? errorCode = _unset,
    Object? errorMessage = _unset,
    Object? failedStage = _unset,
    int? retryCount,
    Object? lastCheckedAt = _unset,
    bool? fileMissing,
    bool? pollStale,
  }) {
    return Recording(
      id: id,
      name: name,
      fileName: fileName,
      localPath: localPath,
      durationMs: durationMs,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      processingStage: identical(processingStage, _unset)
          ? this.processingStage
          : processingStage as String?,
      remoteTaskId: identical(remoteTaskId, _unset)
          ? this.remoteTaskId
          : remoteTaskId as String?,
      transcript: identical(transcript, _unset)
          ? this.transcript
          : transcript as String?,
      summary: identical(summary, _unset) ? this.summary : summary as String?,
      errorCode:
          identical(errorCode, _unset) ? this.errorCode : errorCode as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      failedStage: identical(failedStage, _unset)
          ? this.failedStage
          : failedStage as String?,
      retryCount: retryCount ?? this.retryCount,
      lastCheckedAt: identical(lastCheckedAt, _unset)
          ? this.lastCheckedAt
          : lastCheckedAt as DateTime?,
      fileMissing: fileMissing ?? this.fileMissing,
      pollStale: pollStale ?? this.pollStale,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'file_name': fileName,
      'local_path': localPath,
      'duration_ms': durationMs,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'status': status.name,
      'processing_stage': processingStage,
      'remote_task_id': remoteTaskId,
      'transcript': transcript,
      'summary': summary,
      'error_code': errorCode,
      'error_message': errorMessage,
      'failed_stage': failedStage,
      'retry_count': retryCount,
      'last_checked_at': lastCheckedAt?.millisecondsSinceEpoch,
    };
  }

  factory Recording.fromMap(
    Map<String, Object?> map, {
    bool fileMissing = false,
  }) {
    final int createdAtMs = (map['created_at']! as num).toInt();
    final int updatedAtMs = (map['updated_at'] as num?)?.toInt() ?? createdAtMs;
    final int? checkedAtMs = (map['last_checked_at'] as num?)?.toInt();
    return Recording(
      id: map['id']! as String,
      name: map['name']! as String,
      fileName: map['file_name']! as String,
      localPath: map['local_path']! as String,
      durationMs: (map['duration_ms']! as num).toInt(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      status: processingStatusFromName(map['status'] as String?),
      processingStage: map['processing_stage'] as String?,
      remoteTaskId: map['remote_task_id'] as String?,
      transcript: map['transcript'] as String?,
      summary: map['summary'] as String?,
      errorCode: map['error_code'] as String?,
      errorMessage: map['error_message'] as String?,
      failedStage: map['failed_stage'] as String?,
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      lastCheckedAt: checkedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(checkedAtMs),
      fileMissing: fileMissing,
    );
  }
}

const Object _unset = Object();
