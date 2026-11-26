import 'dart:convert';

import '../../domain/ai_enums_bridge.dart';
import '../../domain/models/knowledge_models.dart';
import '../repositories/knowledge_repository.dart';
import 'ai_client.dart';

/// 知识库整理计划里的单条文档写入操作
class KnowledgeDocUpsert {
  final String slug;
  final String title;
  final String markdown;

  const KnowledgeDocUpsert({
    required this.slug,
    required this.title,
    required this.markdown,
  });
}

/// AI 生成的知识库整理方案
class KnowledgeOrganizePlan {
  final List<KnowledgeDocUpsert> upserts;
  final List<String> deletes;
  final String reply;

  const KnowledgeOrganizePlan({
    required this.upserts,
    required this.deletes,
    required this.reply,
  });

  bool get hasChanges => upserts.isNotEmpty || deletes.isNotEmpty;
}

/// 执行落盘后的汇总结果
class KnowledgeOrganizeResult {
  final List<String> touchedSlugs;
  final List<String> deletedSlugs;
  final String reply;

  const KnowledgeOrganizeResult({
    required this.touchedSlugs,
    required this.deletedSlugs,
    required this.reply,
  });

  String summaryLine() {
    final parts = <String>[];
    if (touchedSlugs.isNotEmpty) {
      parts.add('已更新 ${touchedSlugs.map((s) => 'docs/$s.md').join('、')}');
    }
    if (deletedSlugs.isNotEmpty) {
      parts.add('已移除 ${deletedSlugs.map((s) => 'docs/$s.md').join('、')}');
    }
    return parts.isEmpty ? '知识库无变更' : '${parts.join('，')}，并同步刷新 KNOWLEDGE.md';
  }
}

/// AI 知识库直接写入与专题整理引擎
///
/// 当用户在对话中要求「新增专题」「拆分专题」「迁移知识点」「修改或整理知识库」时，
/// 带着完整的 `docs/*.md` 原文与近期对话调用大模型生成精确的文件级更新方案，
/// 由客户端安全落盘并自动重建 `KNOWLEDGE.md`。
class KnowledgeOrganizer {
  const KnowledgeOrganizer();

  static final RegExp _kbTargetPattern = RegExp(
    r'(?:知识库|专题|docs/|knowledge\.md|分类文档|笔记库)',
    caseSensitive: false,
  );

  static final RegExp _kbMutationVerbPattern = RegExp(
    r'(?:新增|新建|创建|加一个|加个|写入|写进|存进|保存|拆分|拆出|拆成|分出|分离|挪到|移到|迁移|归类|整理|合并|修改|更新|改名|重命名|删除|删掉)',
  );

  static final RegExp _directSplitPattern = RegExp(
    r'(?:单独(?:开|建|放|拆|列)一个|拆成(?:一个)?独立|写进.{0,10}专题|放到.{0,10}专题)',
  );

  /// 判断用户发来的消息是否明确表达了“修改/新建/整理本地知识库”的意图。
  ///
  /// 必须同时命中“知识库对象词”与“操作动词”（或明确拆分句式），避免误伤正常学习提问
  /// （例如“我想学 C++ 专题”或“聊聊知识库里的经济学”不应触发文件改写）。
  static bool looksLikeKnowledgeWriteRequest(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return false;

    if (_directSplitPattern.hasMatch(text)) return true;
    return _kbTargetPattern.hasMatch(text) &&
        _kbMutationVerbPattern.hasMatch(text);
  }

  static const String _organizeSystemPrompt = '''
你是「回响」的知识库结构整理引擎，负责直接对用户的本地 `docs/<slug>.md` 文档执行新增、拆分、迁移、整理或删除操作。
只输出合法 JSON，不要输出任何 JSON 之外的解释或 Markdown 代码块包裹外的文字。

## 绝对规则
1. **完整保留历史笔记**：从旧文档拆分或迁移已有知识卡片时，**必须逐字完整保留**原卡片的 `## 主题 YYYY-MM-DD` 标题（保留原有反引号日期）以及下面的 `- 核心：`、`- 类比：`、`- 误区：`、`- 复述：` 等字段，绝不允许擅自删减、改写丢细节或丢失日期。
2. **文件格式规范**：
   - 每个文件首行必须是 `# 专题名称`（例如 `# C++`）。
   - 如果用户只是要求“新增一个空白专题”且没有现成内容可迁入，只需输出 `"# 专题名称"` 即可，不要编造假笔记。
   - 如果需要把近期对话里刚聊透的新知识点写进某专题，请按卡片四要素格式整理：
     ```markdown
     ## 主题名称 `YYYY-MM-DD`
     - 核心：...
     - 类比：...
     - 误区：...
     - 复述：...
     ```
3. **Slug 规范**：使用纯小写 ASCII 字母、数字或连字符（如 `cpp`、`programming`、`economics`、`physics`），优先复用已有文件 slug；C++ 必须使用 `cpp`。
4. **最小改动**：只输出内容确实发生新增或变化的 `upserts`；只有当文档全部条目被迁空且原专题不再需要保留、或用户明确要求删除时才放入 `deletes`。
5. **reply 口吻**：用自然平实、像朋友聊天的口语（40~140 字）向用户确认已经写入/拆分好了哪些专题，最后可顺带抛 1 个轻量承接问题。绝不夸赞、不用“咱”、不说“我没有文件读写权限”。

严格按如下 JSON 结构输出：
{
  "upserts": [
    {
      "slug": "cpp",
      "title": "C++",
      "markdown": "# C++\\n\\n## ..."
    }
  ],
  "deletes": [],
  "reply": "已经帮你建好 C++ 专题，把原来放在编程与软件里的 C++ 笔记都拆过去了。接下来你想先复习哪一条，还是继续聊个新问题？"
}
''';

  Future<KnowledgeOrganizePlan> plan({
    required AiClient aiClient,
    required String instruction,
    required String knowledgeIndex,
    required Map<String, String> allDocs,
    List<StudyMessage> recentMessages = const [],
    DateTime? now,
  }) async {
    final today = now ?? DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final payload = StringBuffer()
      ..writeln('【今天日期】$dateStr')
      ..writeln()
      ..writeln('【用户当前指令】')
      ..writeln(instruction.trim())
      ..writeln();

    if (knowledgeIndex.trim().isNotEmpty) {
      payload
        ..writeln('【当前 KNOWLEDGE.md 总索引】')
        ..writeln(knowledgeIndex.trim())
        ..writeln();
    }

    if (allDocs.isEmpty) {
      payload.writeln('【当前 docs/ 目录】为空（尚无专题文档）');
    } else {
      payload.writeln('【当前所有 docs/*.md 完整原文】');
      for (final entry in allDocs.entries) {
        payload
          ..writeln('--- FILE: docs/${entry.key}.md ---')
          ..writeln(entry.value.trim())
          ..writeln();
      }
    }

    if (recentMessages.isNotEmpty) {
      final tail = recentMessages.length > 8
          ? recentMessages.sublist(recentMessages.length - 8)
          : recentMessages;
      payload.writeln('【近期对话记录（供需要沉淀新内容时参考）】');
      for (final m in tail) {
        final speaker = m.role == StudyMessageRole.user ? '用户' : '回响';
        payload.writeln('$speaker：${m.content.trim()}');
      }
    }

    final raw = await aiClient.chat(
      [
        const AiMessage.system(_organizeSystemPrompt),
        AiMessage.user(payload.toString()),
      ],
      enableWebSearch: false,
    );

    return parsePlanResponse(raw, existingDocs: allDocs);
  }

  KnowledgeOrganizePlan parsePlanResponse(
    String rawResponse, {
    Map<String, String> existingDocs = const {},
  }) {
    final jsonStr = _extractJsonObject(rawResponse);
    if (jsonStr == null) {
      throw const FormatException('知识库整理结果未能解析为 JSON');
    }

    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map) {
      throw const FormatException('知识库整理结果根结构不是 JSON 对象');
    }

    final map = decoded.cast<String, dynamic>();
    final upserts = <KnowledgeDocUpsert>[];
    final existingSlugs = existingDocs.keys.toSet();

    final rawUpserts = map['upserts'];
    if (rawUpserts is List) {
      for (final item in rawUpserts) {
        if (item is! Map) continue;
        final m = item.cast<String, dynamic>();
        final rawTitle = (m['title'] ?? '').toString().trim();
        final rawSlug = (m['slug'] ?? '').toString().trim();
        final slug = rawSlug.isNotEmpty
            ? KnowledgeRepository.suggestSlug(rawSlug)
            : KnowledgeRepository.suggestSlug(
                rawTitle,
                existingSlugs: existingSlugs,
              );
        var markdown = (m['markdown'] ?? '').toString().trim();
        final title = rawTitle.isNotEmpty ? rawTitle : slug;

        if (markdown.isEmpty) {
          markdown = '# $title';
        } else if (!markdown.startsWith('# ')) {
          markdown = '# $title\n\n$markdown';
        }

        upserts.add(
          KnowledgeDocUpsert(
            slug: slug,
            title: title,
            markdown: markdown,
          ),
        );
      }
    }

    final deletes = <String>[];
    final rawDeletes = map['deletes'];
    if (rawDeletes is List) {
      for (final item in rawDeletes) {
        final s = item.toString().trim();
        if (s.isNotEmpty) {
          deletes.add(KnowledgeEntry.normalizeSlug(s));
        }
      }
    }

    final reply = (map['reply'] ?? '').toString().trim();
    return KnowledgeOrganizePlan(
      upserts: upserts,
      deletes: deletes,
      reply: reply,
    );
  }

  Future<KnowledgeOrganizeResult> applyPlan({
    required KnowledgeRepository repository,
    required KnowledgeOrganizePlan plan,
  }) async {
    await repository.applyUpdates(
      upserts: [
        for (final u in plan.upserts) (slug: u.slug, markdown: u.markdown),
      ],
      deletes: plan.deletes,
    );

    final touchedSlugs = plan.upserts.map((u) => u.slug).toList();
    final deletedSlugs = plan.deletes;
    final reply = plan.reply.isNotEmpty
        ? plan.reply
        : (plan.hasChanges
            ? '已经帮你在知识库里整理好了（${touchedSlugs.map((s) => 'docs/$s.md').join('、')}），打开左上角菜单就能看到。你想先看哪一部分？'
            : '知识库当前没有需要修改的地方。你想针对哪一块继续聊聊，还是新建一个专题？');

    return KnowledgeOrganizeResult(
      touchedSlugs: touchedSlugs,
      deletedSlugs: deletedSlugs,
      reply: reply,
    );
  }

  String? _extractJsonObject(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final fenceMatch =
        RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
            .firstMatch(trimmed);
    final candidate = (fenceMatch?.group(1) ?? trimmed).trim();

    final firstBrace = candidate.indexOf('{');
    final lastBrace = candidate.lastIndexOf('}');
    if (firstBrace == -1 || lastBrace <= firstBrace) return null;
    return candidate.substring(firstBrace, lastBrace + 1);
  }
}
