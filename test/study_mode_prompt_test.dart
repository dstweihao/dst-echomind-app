import 'package:echomind_app/data/ai/ai_client.dart';
import 'package:echomind_app/data/ai/openai_client.dart';
import 'package:echomind_app/data/ai/prompts/study_mode_prompt.dart';
import 'package:echomind_app/domain/models/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatGPT Study Mode 提示词与分层知识注入', () {
    test('系统提示词覆盖四大教学原则与语音朗读友好规范', () {
      const prompt = StudyModePrompt.systemPrompt;
      expect(prompt, contains('轻量摸底'));
      expect(prompt, contains('生活类比'));
      expect(prompt, contains('仅抛出 1 个'));
      expect(prompt, contains('费曼复述'));
      expect(prompt, contains('语音朗读友好'));
      expect(prompt, contains('代码示例'));
      expect(prompt, contains('Markdown 代码块'));
      expect(StudyModePrompt.starterPrompts.length, greaterThanOrEqualTo(4));
    });

    test('buildSystemPrompt 自动注入 KNOWLEDGE.md、压缩摘要与按需复习专题', () {
      final built = StudyModePrompt.buildSystemPrompt(
        knowledgeIndex: '# KNOWLEDGE\n- **通货膨胀**：钱变多购买力降',
        rollingSummary: '刚刚聊完货币供应量。',
        focusedDocTitle: '经济学与金融',
        focusedDocContent: '## 通货膨胀\n- 小岛苹果类比',
      );
      expect(built, contains('用户已沉淀的知识地图（KNOWLEDGE.md）'));
      expect(built, contains('通货膨胀'));
      expect(built, contains('前期对话压缩摘要'));
      expect(built, contains('刚刚聊完货币供应量'));
      expect(built, contains('当前按需挂载的复习专题文档（经济学与金融）'));
      expect(built, contains('小岛苹果类比'));
    });

    test('已下线的旧模型名自动迁移至 deepseek-flash', () {
      expect(
        AiSettings.fromMap({'model': 'deepseek-reasoner'}).model,
        'deepseek-flash',
      );
      expect(
        AiSettings.fromMap({'model': 'deepseek-chat'}).model,
        'deepseek-flash',
      );
      expect(
        AiSettings.fromMap({'model': 'deepseek-v4-pro'}).model,
        'deepseek-v4-pro',
      );
    });

    test('deepseek-flash 正确传递 thinking 开关参数', () {
      final fastClient = OpenAiClient(
        settings: const AiSettings(
          baseUrl: 'https://api.deepseek.com',
          model: 'deepseek-flash',
          enableThinking: false,
        ),
        apiKey: 'sk-test',
      );
      final fastBody = fastClient.buildBody(
        const [AiMessage.user('你好')],
        stream: true,
      );
      expect(fastBody['model'], 'deepseek-flash');
      expect(fastBody['thinking'], {'type': 'disabled'});
      expect(fastBody.containsKey('reasoning_effort'), false);

      final thinkClient = OpenAiClient(
        settings: const AiSettings(
          baseUrl: 'https://api.deepseek.com',
          model: 'deepseek-flash',
          enableThinking: true,
          reasoningEffort: 'high',
        ),
        apiKey: 'sk-test',
      );
      final thinkBody = thinkClient.buildBody(
        const [AiMessage.user('解这道微积分')],
        stream: true,
      );
      expect(thinkBody['thinking'], {'type': 'enabled'});
      expect(thinkBody['reasoning_effort'], 'high');
    });

    test('ASR 与 TTS 端点地址拼接正确', () {
      const s = AiSettings(
        baseUrl: 'https://api.deepseek.com/',
        ttsVoiceId: 'stella',
      );
      expect(s.asrEndpoint, 'https://api.deepseek.com/v1/tools/asr');
      expect(s.ttsHttpEndpoint, 'https://api.deepseek.com/v1/tools/tts');
      expect(
        s.ttsWebSocketUri().toString(),
        'wss://api.deepseek.com/v1/tools/tts?voice_id=stella&format=pcm&filter_markdown=true',
      );
    });
  });
}
