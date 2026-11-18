import 'package:echomind_app/data/ai/ai_client.dart';
import 'package:echomind_app/data/ai/anthropic_client.dart';
import 'package:echomind_app/data/ai/openai_client.dart';
import 'package:echomind_app/domain/enums/app_enums.dart';
import 'package:echomind_app/domain/models/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiSettings 端点拼接与校验', () {
    test('OpenAI 端点', () {
      final s = AiSettings(baseUrl: 'https://x.com/', protocol: AiProtocol.openai);
      expect(s.chatEndpoint, 'https://x.com/chat/completions');
    });

    test('Anthropic 端点', () {
      final s = AiSettings(baseUrl: 'https://x.com', protocol: AiProtocol.anthropic);
      expect(s.chatEndpoint, 'https://x.com/v1/messages');
    });

    test('校验非法配置', () {
      expect(AiSettings(baseUrl: '', model: '').validate(), isNotEmpty);
      expect(AiSettings(baseUrl: 'ftp://x', model: 'm').validate(), isNotEmpty);
      expect(AiSettings(baseUrl: 'https://x.com', model: 'm').validate(), isEmpty);
    });

    test('默认开启联网搜索且支持持久化序列化', () {
      expect(AiSettings.defaults.enableWebSearch, isTrue);
      // 老配置文件缺省 enable_web_search 时默认开启
      expect(AiSettings.fromMap(const {'model': 'deepseek-flash'}).enableWebSearch, isTrue);
      // 显式关闭后能正确往返
      final off = AiSettings.defaults.copyWith(enableWebSearch: false);
      expect(AiSettings.fromMap(off.toMap()).enableWebSearch, isFalse);
    });
  });

  group('OpenAiClient 协议构造', () {
    final client = OpenAiClient(
      settings: const AiSettings(
        protocol: AiProtocol.openai,
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-pro',
        reasoningEffort: 'high',
      ),
      apiKey: 'sk-test',
    );

    test('端点', () {
      expect(client.buildUri(), Uri.parse('https://api.deepseek.com/chat/completions'));
    });

    test('鉴权头', () {
      expect(client.buildHeaders()['Authorization'], 'Bearer sk-test');
    });

    test('请求体', () {
      final body = client.buildBody(
        const [AiMessage.system('你是拆塔官'), AiMessage.user('你好')],
        stream: true,
      );
      expect(body['model'], 'deepseek-v4-pro');
      expect(body['stream'], true);
      expect(body['reasoning_effort'], 'high');
      expect(body['messages'], [
        {'role': 'system', 'content': '你是拆塔官'},
        {'role': 'user', 'content': '你好'},
      ]);
    });

    test('delta 提取：跳过思考内容', () {
      expect(client.extractDelta({'choices': [{'delta': {'content': '你好'}}]}), '你好');
      expect(client.extractDelta({'choices': [{'delta': {'reasoning_content': '思考中'}}]}), isNull);
      expect(client.extractDelta({'choices': []}), isNull);
    });

    test('done 事件判定', () {
      expect(client.isDoneEvent({'choices': [{'finish_reason': 'stop'}]}), true);
      expect(client.isDoneEvent({'choices': [{}]}), false);
    });

    test('服务端错误提取', () {
      expect(client.extractServerError({'error': {'message': '401 bad key'}}), '401 bad key');
    });

    test('开启联网搜索时注入 DeepSeek 服务端工具，关闭时不注入', () {
      final withSearch = client.buildBody(
        const [AiMessage.user('最新新闻')],
        stream: true,
        enableWebSearch: true,
      );
      expect(withSearch['tools'], [
        {'type': 'deepseek_web_search'},
        {'type': 'deepseek_read_url'},
      ]);

      final withoutSearch = client.buildBody(
        const [AiMessage.user('最新新闻')],
        stream: true,
        enableWebSearch: false,
      );
      expect(withoutSearch.containsKey('tools'), isFalse);
    });

    test('流式服务端工具事件提取状态提示', () {
      expect(
        client.extractStatusHint({
          'choices': [
            {
              'server_tool_event': {
                'type': 'call_started',
                'call': {'type': 'deepseek_web_search', 'kind': 'search'},
              },
            },
          ],
        }),
        '正在联网搜索…',
      );
      expect(
        client.extractStatusHint({
          'choices': [
            {
              'server_tool_event': {
                'type': 'call_started',
                'call': {'type': 'deepseek_read_url', 'kind': 'read_link'},
              },
            },
          ],
        }),
        '正在阅读网页…',
      );
    });
  });

  group('AnthropicClient 协议构造', () {
    final client = AnthropicClient(
      settings: const AiSettings(
        protocol: AiProtocol.anthropic,
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-pro',
      ),
      apiKey: 'sk-ant',
    );

    test('端点与鉴权头', () {
      expect(client.buildUri(), Uri.parse('https://api.deepseek.com/v1/messages'));
      expect(client.buildHeaders()['x-api-key'], 'sk-ant');
      expect(client.buildHeaders()['anthropic-version'], '2023-06-01');
      expect(client.buildHeaders().containsKey('Authorization'), false);
    });

    test('system 抽到顶层', () {
      final body = client.buildBody(
        const [AiMessage.system('S'), AiMessage.user('U'), AiMessage.assistant('A')],
        stream: true,
      );
      expect(body['system'], 'S');
      expect(body['messages'], [
        {'role': 'user', 'content': 'U'},
        {'role': 'assistant', 'content': 'A'},
      ]);
    });

    test('delta 提取', () {
      expect(client.extractDelta({'type': 'content_block_delta', 'delta': {'text': 'x'}}), 'x');
      expect(client.extractDelta({'type': 'message_start'}), isNull);
    });

    test('done 事件判定', () {
      expect(client.isDoneEvent({'type': 'message_stop'}), true);
      expect(client.isDoneEvent({'type': 'content_block_delta'}), false);
    });

    test('全文提取（只取 text 块）', () {
      expect(
        client.extractFullText({
          'content': [
            {'type': 'text', 'text': 'a'},
            {'type': 'text', 'text': 'b'},
            {'type': 'tool_use'},
          ],
        }),
        'ab',
      );
    });
  });

  group('AiErrorKind 分类', () {
    test('用户提示', () {
      expect(AiErrorKind.unauthorized.userMessage, contains('API Key'));
    });

    test('是否可重试', () {
      expect(AiErrorKind.network.isRetryable, true);
      expect(AiErrorKind.rateLimited.isRetryable, true);
      expect(AiErrorKind.server.isRetryable, true);
      expect(AiErrorKind.unauthorized.isRetryable, false);
    });

    test('是否降级自评而非中断', () {
      expect(AiErrorKind.server.shouldDegradeGracefully, true);
      expect(AiErrorKind.unauthorized.shouldDegradeGracefully, true);
      expect(AiErrorKind.cancelled.shouldDegradeGracefully, false);
    });
  });
}
