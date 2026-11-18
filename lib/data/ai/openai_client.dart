import 'ai_client.dart';
import 'base_ai_client.dart';

/// OpenAI 兼容协议客户端
///
/// 端点：`POST {base_url}/chat/completions`
/// 覆盖 DeepSeek（含最新 `deepseek-flash` thinking 开关与 `deepseek-v4-pro`）及主流兼容平台。
class OpenAiClient extends BaseAiClient {
  OpenAiClient({
    required super.settings,
    required super.apiKey,
    super.httpClient,
  });

  @override
  Uri buildUri() => Uri.parse(settings.chatEndpoint);

  @override
  Map<String, String> buildHeaders() => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

  @override
  Map<String, dynamic> buildBody(
    List<AiMessage> messages, {
    required bool stream,
    bool enableWebSearch = false,
  }) {
    final body = <String, dynamic>{
      'model': settings.model,
      'messages': messages
          .map((m) => {
                'role': m.role.wireName,
                'content': m.images.isEmpty
                    ? m.content
                    : [
                        if (m.content.isNotEmpty)
                          {'type': 'text', 'text': m.content},
                        for (final img in m.images)
                          {
                            'type': 'image_url',
                            'image_url': {'url': img.dataUrl},
                          },
                      ],
              })
          .toList(),
      'stream': stream,
      'temperature': settings.temperature,
      'max_tokens': settings.maxTokens,
    };

    final effort = settings.reasoningEffort;
    final isDeepSeekFlash = settings.isDeepSeekEndpoint &&
        settings.model.trim().toLowerCase() == 'deepseek-flash';

    if (isDeepSeekFlash) {
      // DeepSeek-V4.1-Flash 默认开启深度思考；显式传递 thinking.type 精确控制延迟与推理深度
      body['thinking'] = {
        'type': settings.enableThinking ? 'enabled' : 'disabled',
      };
      if (settings.enableThinking && effort != null && effort.isNotEmpty) {
        body['reasoning_effort'] = effort;
      }
    } else if (effort != null && effort.isNotEmpty) {
      body['reasoning_effort'] = effort;
    }

    if (enableWebSearch && settings.isDeepSeekEndpoint) {
      body['tools'] = const [
        {'type': 'deepseek_web_search'},
        {'type': 'deepseek_read_url'},
      ];
    }

    return body;
  }

  @override
  String? extractStatusHint(Map<String, dynamic> event) {
    final choices = event['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final toolEvent = first['server_tool_event'];
    if (toolEvent is! Map) return null;
    if (toolEvent['type']?.toString() != 'call_started') return null;

    final call = toolEvent['call'];
    if (call is! Map) return '正在联网搜索…';
    final callType = call['type']?.toString() ?? '';
    final callKind = call['kind']?.toString() ?? '';
    if (callType == 'deepseek_read_url' ||
        callKind == 'read_link' ||
        callKind == 'open_page') {
      return '正在阅读网页…';
    }
    return '正在联网搜索…';
  }

  @override
  String? extractDelta(Map<String, dynamic> event) {
    final choices = event['choices'];
    if (choices is! List || choices.isEmpty) return null;

    final first = choices.first;
    if (first is! Map) return null;

    // 流式：只取 delta.content 正文，跳过 reasoning_content 避免语音播报内部草稿
    final delta = first['delta'];
    if (delta is Map) {
      final content = delta['content'];
      if (content is String && content.isNotEmpty) return content;
    }

    // 非流式兜底：message.content
    final message = first['message'];
    if (message is Map) {
      final content = message['content'];
      if (content is String) return content;
    }

    return null;
  }

  @override
  bool isDoneEvent(Map<String, dynamic> event) {
    final choices = event['choices'];
    if (choices is! List || choices.isEmpty) return false;
    final first = choices.first;
    if (first is! Map) return false;
    return first['finish_reason'] != null;
  }

  @override
  String extractFullText(Map<String, dynamic> response) {
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final first = choices.first;
    if (first is! Map) return '';
    final message = first['message'];
    if (message is! Map) return '';
    return (message['content'] ?? '').toString();
  }

  @override
  String? extractServerError(Map<String, dynamic> body) {
    final error = body['error'];
    if (error is Map) {
      final msg = error['message'];
      if (msg != null) return msg.toString();
    }
    if (error is String) return error;
    final msg = body['message'];
    return msg?.toString();
  }
}
