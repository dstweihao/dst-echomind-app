import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// DeepSeek ASR 语音识别异常
class AsrException implements Exception {
  final String message;
  final int? statusCode;

  const AsrException(this.message, {this.statusCode});

  @override
  String toString() =>
      'AsrException(${statusCode != null ? 'HTTP $statusCode: ' : ''}$message)';
}

/// DeepSeek ASR 识别结果
class AsrResult {
  final String text;
  final int durationMs;
  final String requestId;

  const AsrResult({
    required this.text,
    this.durationMs = 0,
    this.requestId = '',
  });
}

/// DeepSeek 官方语音转文字客户端
///
/// 端点：`POST https://api.deepseek.com/v1/tools/asr`
/// 格式：`multipart/form-data`，`file` 字段上传 16-bit PCM WAV 或 Ogg Opus（≤ 8 MiB，≤ 120 秒）。
class DeepSeekAsrClient {
  static const int maxFileSizeBytes = 8 * 1024 * 1024;

  final String endpoint;
  final String apiKey;
  final http.Client _http;
  final bool _ownsClient;
  final Duration timeout;

  DeepSeekAsrClient({
    required this.endpoint,
    required this.apiKey,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  })  : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// 将 WAV 音频字节转写为文字
  Future<AsrResult> transcribeWav(
    Uint8List wavBytes, {
    String filename = 'speech.wav',
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const AsrException('请先在设置中配置 DeepSeek API Key');
    }
    if (wavBytes.length <= 44) {
      throw const AsrException('录音时间太短，没有检测到有效声音');
    }
    if (wavBytes.length > maxFileSizeBytes) {
      throw const AsrException('单次录音文件超过 8MB 上限，请缩短说话时长');
    }

    final uri = Uri.parse(endpoint);
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          wavBytes,
          filename: filename,
        ),
      );

    try {
      final streamed = await _http.send(request).timeout(timeout);
      final bodyBytes = await streamed.stream.toBytes();
      final bodyText = utf8.decode(bodyBytes, allowMalformed: true);

      if (streamed.statusCode != 200) {
        throw _mapError(streamed.statusCode, bodyText);
      }

      final decoded = jsonDecode(bodyText);
      if (decoded is! Map) {
        throw const AsrException('语音识别返回格式异常');
      }

      final text = (decoded['text'] ?? '').toString().trim();
      final durationMs = (decoded['duration_ms'] is num)
          ? (decoded['duration_ms'] as num).toInt()
          : 0;
      final requestId = (decoded['request_id'] ?? '').toString();

      return AsrResult(
        text: text,
        durationMs: durationMs,
        requestId: requestId,
      );
    } on AsrException {
      rethrow;
    } on TimeoutException {
      throw const AsrException('语音识别超时，请检查网络后重试');
    } catch (e) {
      throw AsrException('语音识别失败：$e');
    }
  }

  AsrException _mapError(int statusCode, String bodyText) {
    String detail = '';
    try {
      final decoded = jsonDecode(bodyText);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map && err['message'] != null) {
          detail = err['message'].toString();
        } else if (decoded['message'] != null) {
          detail = decoded['message'].toString();
        }
      }
    } catch (_) {}

    final msg = switch (statusCode) {
      401 || 403 => 'API Key 无效或无语音识别权限，请检查密钥',
      400 => detail.isNotEmpty ? '音频无法识别：$detail' : '音频格式不受支持或内容为空',
      413 => '单次录音体积超限（最大 8MB）',
      429 => '语音识别请求过于频繁或账户余额不足',
      >= 500 => 'DeepSeek 语音服务暂时繁忙，请稍后重试',
      _ => detail.isNotEmpty ? detail : '语音识别异常 (HTTP $statusCode)',
    };
    return AsrException(msg, statusCode: statusCode);
  }

  void dispose() {
    if (_ownsClient) {
      _http.close();
    }
  }
}
