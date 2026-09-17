import 'package:echonote/models/processing_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps backend stages onto client transcribing until both results exist', () {
    expect(
      mapRemoteTranscription(
        const RemoteTranscription(id: 't1', status: 'queued'),
      ).status,
      ProcessingStatus.transcribing,
    );
    expect(
      mapRemoteTranscription(
        const RemoteTranscription(id: 't1', status: 'transcribing'),
      ).processingStage,
      'transcribing',
    );
    expect(
      processingStatusLabel(ProcessingStatus.transcribing, stage: 'summarizing'),
      '生成摘要中',
    );
    final MappedRemoteState completed = mapRemoteTranscription(
      const RemoteTranscription(
        id: 't1',
        status: 'completed',
        transcript: '全文',
        summary: '摘要',
      ),
    );
    expect(completed.status, ProcessingStatus.completed);
  });

  test('completed without summary is treated as summarizing failure', () {
    final MappedRemoteState incomplete = mapRemoteTranscription(
      const RemoteTranscription(
        id: 't1',
        status: 'completed',
        transcript: '全文',
      ),
    );
    expect(incomplete.status, ProcessingStatus.failed);
    expect(incomplete.failedStage, 'summarizing');
  });

  test('summary failure keeps transcript and retries remote only', () {
    final MappedRemoteState failed = mapRemoteTranscription(
      const RemoteTranscription(
        id: 't1',
        status: 'failed',
        transcript: '已有全文',
        errorCode: 'LLM_NOT_CONFIGURED',
        message: '未配置摘要服务',
      ),
    );
    expect(failed.status, ProcessingStatus.failed);
    expect(failed.transcript, '已有全文');
    expect(failed.failedStage, 'summarizing');
    expect(
      retryActionFor(
        status: ProcessingStatus.failed,
        remoteTaskId: 't1',
        failedStage: 'summarizing',
      ),
      RetryAction.remoteRetry,
    );
  });

  test('upload failure retries from upload', () {
    expect(
      retryActionFor(
        status: ProcessingStatus.failed,
        failedStage: 'upload',
      ),
      RetryAction.upload,
    );
    expect(canUploadRecording(ProcessingStatus.pendingUpload), isTrue);
    expect(canDeleteRecording(ProcessingStatus.transcribing), isFalse);
    expect(canDeleteRecording(ProcessingStatus.pendingUpload), isTrue);
    expect(isTransientQueryError('INTERNAL_ERROR'), isTrue);
    expect(isTransientQueryError('TASK_NOT_FOUND'), isFalse);
    expect(
      isInterruptedUpload(
        status: ProcessingStatus.uploading,
        remoteTaskId: null,
      ),
      isTrue,
    );
  });
}
