/// 客户端处理态。页面文案只有这五个主状态；「生成摘要中」是 transcribing 的 stage。
enum ProcessingStatus {
  pendingUpload,
  uploading,
  transcribing,
  completed,
  failed,
}

enum RetryAction { upload, remoteRetry }

ProcessingStatus processingStatusFromName(String? raw) {
  for (final ProcessingStatus value in ProcessingStatus.values) {
    if (value.name == raw) {
      return value;
    }
  }
  return ProcessingStatus.pendingUpload;
}

String processingStatusLabel(ProcessingStatus status, {String? stage}) {
  switch (status) {
    case ProcessingStatus.pendingUpload:
      return '待上传';
    case ProcessingStatus.uploading:
      return '上传中';
    case ProcessingStatus.transcribing:
      return switch (stage) {
        'summarizing' => '生成摘要中',
        'queued' => '等待处理',
        _ => '转写处理中',
      };
    case ProcessingStatus.completed:
      return '已完成';
    case ProcessingStatus.failed:
      return '处理失败';
  }
}

/// 后端任务快照。字段名和 Node 的 toPublicTask 对齐。
class RemoteTranscription {
  const RemoteTranscription({
    required this.id,
    required this.status,
    this.stage,
    this.transcript,
    this.summary,
    this.errorCode,
    this.message,
  });

  final String id;
  final String status;
  final String? stage;
  final String? transcript;
  final String? summary;
  final String? errorCode;
  final String? message;

  factory RemoteTranscription.fromJson(Map<String, Object?> json) {
    return RemoteTranscription(
      id: json['id'] as String,
      status: json['status'] as String,
      stage: json['stage'] as String?,
      transcript: json['transcript'] as String?,
      summary: json['summary'] as String?,
      errorCode: json['errorCode'] as String?,
      message: json['message'] as String?,
    );
  }
}

class MappedRemoteState {
  const MappedRemoteState({
    required this.status,
    this.processingStage,
    this.transcript,
    this.summary,
    this.errorCode,
    this.errorMessage,
    this.failedStage,
  });

  final ProcessingStatus status;
  final String? processingStage;
  final String? transcript;
  final String? summary;
  final String? errorCode;
  final String? errorMessage;
  final String? failedStage;
}

/// 后端 queued / transcribing / summarizing 对用户都是「处理中」，
/// 只有 completed / failed 才切本地终态，避免把「摘要中」显示成已完成。
MappedRemoteState mapRemoteTranscription(RemoteTranscription task) {
  switch (task.status) {
    case 'queued':
      return MappedRemoteState(
        status: ProcessingStatus.transcribing,
        processingStage: 'queued',
        transcript: task.transcript,
        summary: task.summary,
      );
    case 'transcribing':
      return MappedRemoteState(
        status: ProcessingStatus.transcribing,
        processingStage: 'transcribing',
        transcript: task.transcript,
        summary: task.summary,
      );
    case 'summarizing':
      return MappedRemoteState(
        status: ProcessingStatus.transcribing,
        processingStage: 'summarizing',
        transcript: task.transcript,
        summary: task.summary,
      );
    case 'completed':
      final bool complete = (task.transcript ?? '').isNotEmpty &&
          (task.summary ?? '').isNotEmpty;
      if (!complete) {
        return MappedRemoteState(
          status: ProcessingStatus.failed,
          transcript: task.transcript,
          summary: task.summary,
          errorCode: 'INCOMPLETE',
          errorMessage: '结果不完整，请重试。',
          failedStage:
              (task.transcript ?? '').isNotEmpty ? 'summarizing' : 'transcribing',
        );
      }
      return MappedRemoteState(
        status: ProcessingStatus.completed,
        transcript: task.transcript,
        summary: task.summary,
      );
    case 'failed':
      return MappedRemoteState(
        status: ProcessingStatus.failed,
        processingStage: null,
        transcript: task.transcript,
        summary: task.summary,
        errorCode: task.errorCode,
        errorMessage: task.message ?? '处理失败，请重试。',
        failedStage: failedStageFromRemote(
          errorCode: task.errorCode,
          transcript: task.transcript,
        ),
      );
    default:
      return MappedRemoteState(
        status: ProcessingStatus.transcribing,
        processingStage: task.stage,
        transcript: task.transcript,
        summary: task.summary,
      );
  }
}

/// LLM_ 前缀或已有全文，说明转写过了，重试应从摘要开始。
String failedStageFromRemote({String? errorCode, String? transcript}) {
  final String code = errorCode ?? '';
  if (code.startsWith('LLM_')) {
    return 'summarizing';
  }
  if ((transcript ?? '').isNotEmpty && code == 'SERVER_INTERRUPTED') {
    return 'summarizing';
  }
  if (code.startsWith('ASR_') || code == 'SERVER_INTERRUPTED') {
    return 'transcribing';
  }
  if ((transcript ?? '').isNotEmpty) {
    return 'summarizing';
  }
  return 'transcribing';
}

/// 摘要失败必须走 remoteRetry，否则会重新上传音频、重复计费。
RetryAction retryActionFor({
  required ProcessingStatus status,
  String? remoteTaskId,
  String? failedStage,
}) {
  if (status != ProcessingStatus.failed) {
    return RetryAction.upload;
  }
  if (failedStage == 'upload' || remoteTaskId == null || remoteTaskId.isEmpty) {
    return RetryAction.upload;
  }
  return RetryAction.remoteRetry;
}

bool canDeleteRecording(ProcessingStatus status) {
  return status != ProcessingStatus.uploading &&
      status != ProcessingStatus.transcribing;
}

bool canUploadRecording(ProcessingStatus status, {String? failedStage}) {
  if (status == ProcessingStatus.pendingUpload) {
    return true;
  }
  return status == ProcessingStatus.failed && failedStage == 'upload';
}

/// GET 失败默认当瞬时错误：任务可能还在跑，不能把本地打成失败。
bool isTransientQueryError(String code) {
  return code != 'TASK_NOT_FOUND' &&
      code != 'NOT_FOUND' &&
      code != 'HTTP_404';
}

/// 上传中途杀进程时还没有 remoteTaskId，重启后必须回到可重试，否则会卡死。
bool isInterruptedUpload({
  required ProcessingStatus status,
  String? remoteTaskId,
}) {
  if (status == ProcessingStatus.uploading) {
    return true;
  }
  return status == ProcessingStatus.transcribing &&
      (remoteTaskId == null || remoteTaskId.isEmpty);
}
