import 'dart:convert';

import 'package:echomind_app/data/ai/ai_client.dart';
import 'package:echomind_app/data/ai/context_compactor.dart';
import 'package:echomind_app/domain/ai_enums_bridge.dart';
import 'package:echomind_app/domain/models/knowledge_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAiClient implements AiClient {
  final String reply;
  _StubAiClient(this.reply);

  @override
  Future<String> chat(
    List<AiMessage> messages, {
    bool? enableWebSearch,
  }) async =>
      reply;

  @override
  Stream<AiChunk> streamChat(
    List<AiMessage> messages, {
    bool? enableWebSearch,
  }) async* {
    yield AiChunk(reply);
    yield AiChunk.done;
  }

  @override
  Future<void> testConnection() async {}

  @override
  void cancel() {}

  @override
  void dispose() {}
}

void main() {
  group('ContextCompactor', () {
    final compactor = ContextCompactor();

    test('每新增 6 条对话（3 轮问答）自动触发静默知识沉淀，并遵守水位线不重复触发', () {
      final msgs = List.generate(
        6,
        (i) => StudyMessage(
          id: '$i',
          role: i.isEven ? StudyMessageRole.user : StudyMessageRole.assistant,
          content: '对话 $i',
          createdAt: DateTime(2026, 11, 17),
        ),
      );
      expect(compactor.shouldAutoDistill(msgs, lastDistilledCount: 0), true);
      expect(compactor.shouldAutoDistill(msgs, lastDistilledCount: 2), false);
      expect(compactor.shouldAutoDistill(msgs, lastDistilledCount: 6), false);
    });

    test('达到消息条数或字符数上限触发自动压缩，分隔提示卡不计入上限', () {
      final few = List.generate(
        10,
        (i) => StudyMessage(
          id: '$i',
          role: StudyMessageRole.user,
          content: '短消息 $i',
          createdAt: DateTime(2026, 11, 17),
        ),
      );
      expect(compactor.shouldAutoCompact(few), false);

      final many = List.generate(
        ContextCompactor.autoCompactMessageThreshold,
        (i) => StudyMessage(
          id: '$i',
          role: StudyMessageRole.user,
          content: '消息 $i',
          createdAt: DateTime(2026, 11, 17),
        ),
      );
      expect(compactor.shouldAutoCompact(many), true);

      final hugeText = [
        StudyMessage(
          id: 'big',
          role: StudyMessageRole.assistant,
          content: '字' * ContextCompactor.autoCompactCharThreshold,
          createdAt: DateTime(2026, 11, 17),
        ),
      ];
      expect(compactor.shouldAutoCompact(hugeText), true);
    });

    test('正确解析被 Markdown 代码块包裹的沉淀 JSON', () async {
      final jsonPayload = jsonEncode({
        'rolling_summary': '用户刚学通通货膨胀直觉，下一步准备聊利率。',
        'entries': [
          {
            'category_slug': 'economics',
            'category_name': '经济学',
            'topic': '通货膨胀',
            'one_liner': '货币超发导致购买力下降。',
            'analogy': '小岛苹果模型',
            'misconception': '',
            'feynman_note': '钱多了东西没多。',
          },
        ],
      });

      final client = _StubAiClient('好的，结果如下：\n```json\n$jsonPayload\n```');
      final res = await compactor.compact(
        aiClient: client,
        previousSummary: '',
        existingKnowledgeIndex: '',
        messagesToCompact: [
          StudyMessage(
            id: '1',
            role: StudyMessageRole.user,
            content: '通货膨胀是什么',
            createdAt: DateTime(2026, 11, 17),
          ),
        ],
      );

      expect(res.rollingSummary, contains('利率'));
      expect(res.entries.length, 1);
      expect(res.entries.first.categorySlug, 'economics');
      expect(res.entries.first.topic, '通货膨胀');
    });

    test('纯闲聊返回空 entries 时仅压缩摘要不往知识库灌水', () {
      final res = compactor.parseCompactionResponse(
        '{"rolling_summary":"简单打了个招呼","entries":[]}',
        fallbackSummary: '',
        compactedCount: 2,
      );
      expect(res.rollingSummary, '简单打了个招呼');
      expect(res.entries, isEmpty);
    });

    test('非法 JSON 抛出 FormatException 保护原对话不丢失', () {
      expect(
        () => compactor.parseCompactionResponse(
          '这不是合法json',
          fallbackSummary: 'old',
          compactedCount: 2,
        ),
        throwsFormatException,
      );
    });
  });
}
