import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/models/ai_settings.dart';
import 'wav_encoder.dart';

/// DeepSeek TTS 异常
class TtsException implements Exception {
  final String message;
  final int? statusCode;

  const TtsException(this.message, {this.statusCode});

  @override
  String toString() =>
      'TtsException(${statusCode != null ? 'HTTP $statusCode: ' : ''}$message)';
}

/// 抽象 WebSocket 通道，便于在单测中无网 Mock DeepSeek TTS 流式协议
abstract class TtsSocketChannel {
  /// 服务端下行帧：文本（JSON 控制消息）或二进制（PCM 音频字节）
  Stream<dynamic> get stream;

  /// 发送 JSON 文本控制帧
  void sendTextFrame(String text);

  /// 关闭连接
  Future<void> close();
}

/// 四端原生（Android / iOS / macOS / Windows）dart:io WebSocket 实现
class IoTtsSocketChannel implements TtsSocketChannel {
  final WebSocket _socket;

  IoTtsSocketChannel(this._socket);

  static Future<TtsSocketChannel> connect(
    Uri uri, {
    required Map<String, dynamic> headers,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: headers,
    ).timeout(timeout);
    return IoTtsSocketChannel(socket);
  }

  @override
  Stream<dynamic> get stream => _socket;

  @override
  void sendTextFrame(String text) {
    if (_socket.readyState == WebSocket.open) {
      _socket.add(text);
    }
  }

  @override
  Future<void> close() async {
    try {
      await _socket.close();
    } catch (_) {}
  }
}

typedef TtsSocketConnector = Future<TtsSocketChannel> Function(
  Uri uri, {
  required Map<String, dynamic> headers,
});

/// 一次实时流式 TTS 会话（对应一条 AI 回复的边生成边播报）
class DeepSeekTtsStreamSession {
  final TtsSocketChannel _channel;
  final StreamController<Uint8List> _audioController =
      StreamController<Uint8List>();
  final Completer<void> _doneCompleter = Completer<void>();

  StreamSubscription<dynamic>? _sub;
  bool _closed = false;
  bool _finishedText = false;

  DeepSeekTtsStreamSession(this._channel) {
    _sub = _channel.stream.listen(
      _onMessage,
      onError: (Object error, StackTrace st) {
        if (!_closed) {
          _audioController.addError(
            error is TtsException ? error : TtsException('语音流中断：$error'),
            st,
          );
        }
        _finish(error);
      },
      onDone: () {
        _finish();
      },
      cancelOnError: true,
    );
  }

  /// 二进制 24kHz 16-bit LE 单声道 PCM 音频分片流
  Stream<Uint8List> get audioChunks => _audioController.stream;

  /// 当服务端返回 `{"event":"finish"}` 或连接结束时完成
  Future<void> get done => _doneCompleter.future;

  bool get isClosed => _closed;

  /// 推送一段增量文本供服务端实时合成
  void sendText(String text) {
    if (_closed || _finishedText) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _channel.sendTextFrame(jsonEncode({
      'event': 'text',
      'text': trimmed,
    }));
  }

  /// 通知服务端所有文本已发送完毕，等待尾段音频合成结束
  void finishText() {
    if (_closed || _finishedText) return;
    _finishedText = true;
    _channel.sendTextFrame(jsonEncode({'event': 'finish_text'}));
  }

  /// 立即中断并释放连接（用于用户打断播报）
  Future<void> cancel() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    _sub = null;
    await _channel.close();
    if (!_audioController.isClosed) {
      await _audioController.close();
    }
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  void _onMessage(dynamic message) {
    if (_closed) return;

    if (message is Uint8List) {
      if (message.isNotEmpty) _audioController.add(message);
      return;
    }
    if (message is List<int>) {
      if (message.isNotEmpty) {
        _audioController.add(Uint8List.fromList(message));
      }
      return;
    }
    if (message is String) {
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map && decoded['event'] == 'finish') {
          final code = (decoded['code'] ?? 'success').toString();
          final detail = (decoded['message'] ?? '').toString();
          if (code != 'success' && !_audioController.isClosed) {
            _audioController.addError(
              TtsException(
                detail.isNotEmpty ? '语音合成中断：$detail' : '语音合成异常 ($code)',
              ),
            );
          }
          _finish();
        }
      } catch (_) {}
    }
  }

  void _finish([Object? error]) {
    if (_closed) return;
    _closed = true;
    _sub?.cancel();
    _sub = null;
    unawaited(_channel.close());
    if (!_audioController.isClosed) {
      unawaited(_audioController.close());
    }
    if (!_doneCompleter.isCompleted) {
      if (error != null) {
        _doneCompleter.completeError(error);
      } else {
        _doneCompleter.complete();
      }
    }
  }
}

/// DeepSeek 官方语音合成客户端（WebSocket 实时流式 + HTTP 重播双通道）
class DeepSeekTtsClient {
  final AiSettings settings;
  final String apiKey;
  final http.Client _http;
  final bool _ownsClient;
  final TtsSocketConnector _socketConnector;

  DeepSeekTtsClient({
    required this.settings,
    required this.apiKey,
    http.Client? httpClient,
    TtsSocketConnector? socketConnector,
  })  : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _socketConnector = socketConnector ?? IoTtsSocketChannel.connect;

  /// 打开 WebSocket 实时流式 TTS 会话（用于 LLM 边生成边播报）
  Future<DeepSeekTtsStreamSession> openStreamSession({
    String? voiceId,
    bool filterMarkdown = true,
  }) async {
    _ensureKey();
    final uri = settings.ttsWebSocketUri(
      voiceId: voiceId ?? settings.ttsVoiceId,
      format: 'pcm',
      filterMarkdown: filterMarkdown,
    );
    try {
      final channel = await _socketConnector(
        uri,
        headers: {'Authorization': 'Bearer ${apiKey.trim()}'},
      );
      return DeepSeekTtsStreamSession(channel);
    } catch (e) {
      throw TtsException('无法连接 DeepSeek 实时语音服务：$e');
    }
  }

  /// HTTP 流式整段合成（用于点击历史气泡重播、试听音色或 WS 失败降级）
  Stream<Uint8List> synthesizeStream(
    String text, {
    String? voiceId,
    bool filterMarkdown = true,
  }) async* {
    _ensureKey();
    final cleaned = stripThinkTags(text);
    if (cleaned.isEmpty) return;

    final request = http.Request('POST', Uri.parse(settings.ttsHttpEndpoint))
      ..headers.addAll({
        'Authorization': 'Bearer ${apiKey.trim()}',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({
        'text': cleaned,
        'voice_id': (voiceId ?? settings.ttsVoiceId).trim().isEmpty
            ? 'stella'
            : (voiceId ?? settings.ttsVoiceId).trim(),
        'format': 'pcm',
        'filter_markdown': filterMarkdown,
      });

    try {
      final response =
          await _http.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        final errBytes = await response.stream.toBytes();
        final errBody = utf8.decode(errBytes, allowMalformed: true);
        throw _mapHttpError(response.statusCode, errBody);
      }

      await for (final chunk in response.stream) {
        if (chunk.isNotEmpty) {
          yield chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        }
      }
    } on TtsException {
      rethrow;
    } on TimeoutException {
      throw const TtsException('语音合成响应超时，请稍后重试');
    } catch (e) {
      throw TtsException('语音合成失败：$e');
    }
  }

  void _ensureKey() {
    if (apiKey.trim().isEmpty) {
      throw const TtsException('请先在设置中配置 DeepSeek API Key');
    }
  }

  TtsException _mapHttpError(int statusCode, String bodyText) {
    final msg = switch (statusCode) {
      401 || 403 => 'API Key 无效或无语音合成权限',
      400 => '文本无法合成语音（可能为空或触发合规过滤）',
      429 => '语音合成并发超限或账户余额不足',
      503 || 504 => '语音合成服务繁忙，请稍后重试',
      _ => bodyText.isNotEmpty
          ? '语音合成失败 (HTTP $statusCode): ${bodyText.substring(0, bodyText.length.clamp(0, 120))}'
          : '语音合成失败 (HTTP $statusCode)',
    };
    return TtsException(msg, statusCode: statusCode);
  }

  void dispose() {
    if (_ownsClient) {
      _http.close();
    }
  }
}
