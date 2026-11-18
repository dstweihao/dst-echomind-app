import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class OcrException implements Exception {
  final String message;
  final int? statusCode;

  const OcrException(this.message, {this.statusCode});

  @override
  String toString() =>
      'OcrException(${statusCode != null ? 'HTTP $statusCode: ' : ''}$message)';
}

class OcrResult {
  final String text;
  final int pageCount;

  const OcrResult({
    required this.text,
    this.pageCount = 0,
  });
}

/// DeepSeek 官方文档与图片 OCR 解析客户端
///
/// 端点：`POST https://api.deepseek.com/v1/tools/ocr`
/// 支持 PDF、Word（DOC/DOCX）、PowerPoint（PPT/PPTX）及常见图片，最大 100 MiB。
class DeepSeekOcrClient {
  static const int maxFileSizeBytes = 100 * 1024 * 1024;
  static const int maxExtractedChars = 24000;

  final String endpoint;
  final String apiKey;
  final http.Client _http;
  final bool _ownsClient;
  final Duration timeout;

  DeepSeekOcrClient({
    required this.endpoint,
    required this.apiKey,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 90),
  })  : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// 解析文档字节并提取干净纯文本
  Future<OcrResult> parseDocument(
    Uint8List fileBytes, {
    required String filename,
    String purpose = 'text_recognition',
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const OcrException('请先在设置中配置 DeepSeek API Key 以解析文档');
    }
    if (fileBytes.isEmpty) {
      throw const OcrException('文件内容为空');
    }
    if (fileBytes.length > maxFileSizeBytes) {
      throw const OcrException('单个文件超过 100MB 上限');
    }

    final uri = Uri.parse(endpoint);
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
      ..fields['purpose'] = purpose
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: filename,
        ),
      );

    try {
      final streamed = await _http.send(request).timeout(timeout);
      final bodyBytes = await streamed.stream.toBytes();
      final bodyText = utf8.decode(bodyBytes, allowMalformed: true).trim();

      if (streamed.statusCode != 200) {
        throw _mapError(streamed.statusCode, bodyText);
      }

      final decoded = jsonDecode(bodyText);
      if (decoded is! Map) {
        throw const OcrException('文档解析返回格式异常');
      }

      final pages = (decoded['pages'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .toList();
      final pageCount = (decoded['page_count'] is num)
          ? (decoded['page_count'] as num).toInt()
          : pages.length;

      final buf = StringBuffer();
      for (var i = 0; i < pages.length; i++) {
        final rawPage = (pages[i]['text'] ?? '').toString();
        final cleaned = cleanOcrMarkup(rawPage);
        if (cleaned.isEmpty) continue;
        if (pages.length > 1) {
          buf.writeln('--- 第 ${i + 1} 页 ---');
        }
        buf.writeln(cleaned);
        if (buf.length >= maxExtractedChars) break;
      }

      var resultText = buf.toString().trim();
      if (resultText.length > maxExtractedChars) {
        resultText =
            '${resultText.substring(0, maxExtractedChars)}\n…（文档较长，已截断前 $maxExtractedChars 字）';
      }

      return OcrResult(text: resultText, pageCount: pageCount);
    } on OcrException {
      rethrow;
    } on TimeoutException {
      throw const OcrException('文档解析超时，请稍后重试');
    } catch (e) {
      throw OcrException('文档解析失败：$e');
    }
  }

  /// 清理 DeepSeek OCR 返回的版面定位标记（如 `<｜box｜>...<｜/box｜>`、`<｜ref｜>...<｜/ref｜>`）
  static String cleanOcrMarkup(String raw) {
    return raw
        .replaceAll(RegExp(r'<[｜|]box[｜|]>[\s\S]*?<[｜|]/box[｜|]>'), '')
        .replaceAll(RegExp(r'<[｜|]det[｜|]>[\s\S]*?<[｜|]/det[｜|]>'), '')
        .replaceAll(RegExp(r'<[｜|]/?ref[｜|]>'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  OcrException _mapError(int statusCode, String bodyText) {
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
      401 || 403 => 'API Key 无效或无文档解析权限',
      400 => detail.isNotEmpty ? '不支持该文件格式：$detail' : '不支持该文件格式或内容异常',
      413 => '文件体积超限（最大 100MB）',
      429 => '文档解析请求过于频繁或账户余额不足',
      >= 500 => 'DeepSeek 文档解析服务繁忙，请稍后重试',
      _ => detail.isNotEmpty ? detail : '文档解析失败 (HTTP $statusCode)',
    };
    return OcrException(msg, statusCode: statusCode);
  }

  void dispose() {
    if (_ownsClient) {
      _http.close();
    }
  }
}
