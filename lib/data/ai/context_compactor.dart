import 'dart:convert';

import '../../domain/ai_enums_bridge.dart';
import '../../domain/models/knowledge_models.dart';
import 'ai_client.dart';

/// 上下文压缩与知识沉淀引擎
///
/// 当单一长期会话的消息数或字符数触及上限（或用户手动触发）时：
/// 1. 把较早的对话提炼为精炼的 `rolling_summary`（工作记忆摘要）；
/// 2. 抽取出真正学通的知识点，按类别/专题/行业归类输出结构化 `KnowledgeEntry`，
///    后续由 [KnowledgeRepository] 追加写入 `docs/<slug>.md` 并刷新总清单 `KNOWLEDGE.md`。
class ContextCompactor {
  /// 静默自动知识沉淀的新增消息条数阈值（每 3 轮问答后台自动提炼沉淀，不折叠当前对话）
  static const int autoDistillNewMessagesThreshold = 6;

  /// 自动触发压缩的消息条数阈值（约 10 轮问答）
  static const int autoCompactMessageThreshold = 20;

  /// 自动触发压缩的累计字符数阈值
  static const int autoCompactCharThreshold = 12000;

  /// 自动压缩后保留在工作记忆里的最近原话条数
  static const int keepRecentMessages = 4;

  static const String _distillSystemPrompt = '''
你是知识沉淀与上下文压缩器。只输出合法 JSON，无解释文字。

## 最高铁律：Sacrifice grammar for the sake of concision.
- 极致信息密度：电报体短语直陈因果，宁可省去主谓宾与完整语法，严禁废话、过渡词、套话、感叹词。
- 符号化压缩：善用 `→`、`vs`、`/` 表达因果与对比。

## 任务
1. `rolling_summary`（≤120字）：合并旧摘要与对话。格式：当前主题 / 已通要点 / 待解问题。
2. `entries`：仅提炼已讲透的硬核收获；闲聊或未懂返回 `[]`，严禁灌水。
   - `category_slug`：通用英文分类（如 `economics`、`programming`、`physics`、`ai`、`math`、`product`、`general`），优先复用 `KNOWLEDGE.md` 已有 slug。
   - `one_liner`（≤28字）：本质机制，极简电报体。
   - `analogy`（≤30字，可空）：核心类比，只留骨架。
   - `misconception`（≤32字，可空）：格式 `误: X → 实: Y`。
   - `feynman_note`（≤24字，可空）：大白话记忆锚点。

严格按此 JSON 输出：
{
  "rolling_summary": "主题: ... | 已通: ... | 待解: ...",
  "entries": [
    {
      "category_slug": "economics",
      "category_name": "经济学与金融",
      "topic": "通货膨胀",
      "one_liner": "货不变、币增发 → 购买力缩水、物价普涨",
      "analogy": "10苹果配100元→配200元，单价翻倍",
      "misconception": "误: 个别商品涨价 → 实: 货币普遍贬值",
      "feynman_note": "币多货少，钱毛了"
    }
  ]
}
''';

  /// 判断当前未沉淀的新增消息是否达到静默自动沉淀条件
  bool shouldAutoDistill(
    List<StudyMessage> messages, {
    required int lastDistilledCount,
  }) {
    final activeCount = messages.where((m) => !m.isCompactionNotice).length;
    return activeCount - lastDistilledCount >= autoDistillNewMessagesThreshold;
  }

  /// 判断当前活跃消息是否达到自动压缩上限
  bool shouldAutoCompact(List<StudyMessage> messages) {
    final active = messages.where((m) => !m.isCompactionNotice).toList();
    if (active.length >= autoCompactMessageThreshold) return true;
    final totalChars = active.fold<int>(0, (sum, m) => sum + m.content.length);
    return totalChars >= autoCompactCharThreshold;
  }

  /// 调用 AI 对指定旧消息切片执行沉淀与压缩
  Future<CompactionResult> compact({
    required AiClient aiClient,
    required String previousSummary,
    required String existingKnowledgeIndex,
    required List<StudyMessage> messagesToCompact,
    DateTime? now,
  }) async {
    if (messagesToCompact.isEmpty) {
      return CompactionResult(
        rollingSummary: previousSummary,
        entries: const [],
        compactedMessageCount: 0,
      );
    }

    final userPayload = StringBuffer();
    if (existingKnowledgeIndex.trim().isNotEmpty) {
      userPayload.writeln('【已有知识总清单 KNOWLEDGE.md（请优先复用其中的 category_slug）】');
      userPayload.writeln(existingKnowledgeIndex.trim());
      userPayload.writeln();
    }
    if (previousSummary.trim().isNotEmpty) {
      userPayload.writeln('【此前的工作记忆摘要】');
      userPayload.writeln(previousSummary.trim());
      userPayload.writeln();
    }
    userPayload.writeln('【待沉淀与压缩的对话记录】');
    for (final m in messagesToCompact) {
      final speaker = m.role == StudyMessageRole.user ? '用户' : '回响';
      userPayload.writeln('$speaker：${m.content.trim()}');
    }

    final rawResponse = await aiClient.chat(
      [
        const AiMessage.system(_distillSystemPrompt),
        AiMessage.user(userPayload.toString()),
      ],
      enableWebSearch: false,
    );

    return parseCompactionResponse(
      rawResponse,
      fallbackSummary: previousSummary,
      compactedCount: messagesToCompact.length,
      now: now,
    );
  }

  /// 解析模型输出的 JSON（兼容被 ```json ... ``` 或前后杂文本包裹的情况）
  CompactionResult parseCompactionResponse(
    String rawResponse, {
    required String fallbackSummary,
    required int compactedCount,
    DateTime? now,
  }) {
    final jsonStr = _extractJsonObject(rawResponse);
    if (jsonStr == null) {
      throw const FormatException('知识沉淀结果未能解析为 JSON');
    }

    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map) {
      throw const FormatException('知识沉淀结果根结构不是 JSON 对象');
    }

    final map = decoded.cast<String, dynamic>();
    final summary = (map['rolling_summary'] ?? '').toString().trim();
    final rawEntries = map['entries'];
    final entries = <KnowledgeEntry>[];

    if (rawEntries is List) {
      for (final item in rawEntries) {
        if (item is Map) {
          final parsed = KnowledgeEntry.fromJson(
            item.cast<String, dynamic>(),
            now: now,
          );
          if (parsed.topic.isNotEmpty && parsed.oneLiner.isNotEmpty) {
            entries.add(parsed);
          }
        }
      }
    }

    return CompactionResult(
      rollingSummary: summary.isNotEmpty ? summary : fallbackSummary,
      entries: entries,
      compactedMessageCount: compactedCount,
    );
  }

  String? _extractJsonObject(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // 1. 优先提取 fenced ```json ... ``` 块
    final fenceMatch =
        RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
            .firstMatch(trimmed);
    final candidate = (fenceMatch?.group(1) ?? trimmed).trim();

    // 2. 截取最外层 { ... }
    final firstBrace = candidate.indexOf('{');
    final lastBrace = candidate.lastIndexOf('}');
    if (firstBrace == -1 || lastBrace <= firstBrace) return null;
    return candidate.substring(firstBrace, lastBrace + 1);
  }
}
