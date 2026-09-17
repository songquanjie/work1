import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/errors/app_error.dart';
import '../../models/processing_status.dart';

/// 对接 Node 转写接口。App 不直连百炼，密钥只在服务端。
class TranscriptionApi {
  TranscriptionApi({
    required this.baseUrl,
    http.Client? client,
    this.uploadTimeout = const Duration(seconds: 60),
    this.queryTimeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final Duration uploadTimeout;
  final Duration queryTimeout;

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Uri _uri(String path) {
    final String root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$root$path');
  }

  Future<RemoteTranscription> createOrReuse({
    required String clientRecordingId,
    required String filePath,
    required String fileName,
  }) async {
    try {
      final http.MultipartRequest request = http.MultipartRequest(
        'POST',
        _uri('/api/transcriptions'),
      );
      request.fields['clientRecordingId'] = clientRecordingId;
      request.files.add(
        await http.MultipartFile.fromPath(
          'audio',
          filePath,
          filename: fileName,
        ),
      );
      final http.StreamedResponse streamed = await _client
          .send(request)
          .timeout(uploadTimeout);
      final http.Response response = await http.Response.fromStream(streamed)
          .timeout(uploadTimeout);
      return _parse(response, upload: true);
    } on AppError {
      rethrow;
    } catch (error) {
      throw _toAppError(error, upload: true);
    }
  }

  Future<RemoteTranscription> getTask(String remoteId) async {
    try {
      final http.Response response = await _client
          .get(_uri('/api/transcriptions/$remoteId'))
          .timeout(queryTimeout);
      return _parse(response, upload: false);
    } on AppError {
      rethrow;
    } catch (error) {
      throw _toAppError(error, upload: false);
    }
  }

  Future<RemoteTranscription> retry(String remoteId) async {
    try {
      final http.Response response = await _client
          .post(_uri('/api/transcriptions/$remoteId/retry'))
          .timeout(queryTimeout);
      return _parse(response, upload: false);
    } on AppError {
      rethrow;
    } catch (error) {
      throw _toAppError(error, upload: false);
    }
  }

  RemoteTranscription _parse(http.Response response, {required bool upload}) {
    Map<String, Object?> json = <String, Object?>{};
    // 按 UTF-8 读 JSON，避免服务端漏 charset 时中文全文被 latin1 解坏。
    final String body = utf8.decode(response.bodyBytes);
    if (body.isNotEmpty) {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map) {
        json = Map<String, Object?>.from(decoded);
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return RemoteTranscription.fromJson(json);
    }
    throw AppError(
      code: (json['errorCode'] as String?) ?? 'HTTP_${response.statusCode}',
      message: (json['message'] as String?) ??
          (upload ? '上传失败，请稍后重试。' : '无法获取处理状态，请稍后重试。'),
    );
  }

  AppError _toAppError(Object error, {required bool upload}) {
    if (error is TimeoutException) {
      return AppError(
        code: 'TIMEOUT',
        message: upload ? '上传超时，请重试。' : '状态暂时无法更新',
      );
    }
    if (error is SocketException || error is http.ClientException) {
      return const AppError(
        code: 'NETWORK',
        message: '网络不可用，请检查连接后重试。',
      );
    }
    return AppError(
      code: 'HTTP',
      message: upload ? '上传失败，请稍后重试。' : '状态暂时无法更新',
    );
  }
}
