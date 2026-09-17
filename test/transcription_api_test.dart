import 'dart:convert';

import 'package:echonote/core/errors/app_error.dart';
import 'package:echonote/data/remote/transcription_api.dart';
import 'package:echonote/models/processing_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('GET maps backend json onto RemoteTranscription', () async {
    http.Request? seen;
    final TranscriptionApi api = TranscriptionApi(
      baseUrl: 'http://192.168.1.8:3000/',
      client: MockClient((http.Request request) async {
        seen = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'id': 'task-1',
            'status': 'summarizing',
            'stage': 'summarizing',
            'transcript': '全文',
            'summary': null,
          }),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );

    final RemoteTranscription result = await api.getTask('task-1');
    expect(seen?.method, 'GET');
    expect(seen?.url.path, '/api/transcriptions/task-1');
    expect(result.id, 'task-1');
    expect(result.status, 'summarizing');
    expect(result.transcript, '全文');
  });

  test('retry 409 keeps backend error code', () async {
    http.Request? seen;
    final TranscriptionApi api = TranscriptionApi(
      baseUrl: 'http://127.0.0.1:3000',
      client: MockClient((http.Request request) async {
        seen = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'errorCode': 'TASK_IN_PROGRESS',
            'message': '任务处理中',
          }),
          409,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );

    await expectLater(
      api.retry('task-1'),
      throwsA(
        isA<AppError>().having(
          (AppError error) => error.code,
          'code',
          'TASK_IN_PROGRESS',
        ),
      ),
    );
    expect(seen?.method, 'POST');
    expect(seen?.url.path, '/api/transcriptions/task-1/retry');
  });

  test('query timeout stays a TIMEOUT app error', () async {
    final TranscriptionApi api = TranscriptionApi(
      baseUrl: 'http://127.0.0.1:3000',
      queryTimeout: const Duration(milliseconds: 20),
      client: MockClient((http.Request request) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.getTask('task-1'),
      throwsA(
        isA<AppError>().having((AppError error) => error.code, 'code', 'TIMEOUT'),
      ),
    );
  });
}
