import 'dart:convert';

import '../../domain/ai_enums_bridge.dart';
import '../../domain/models/knowledge_models.dart';
import '../repositories/knowledge_repository.dart';
import 'ai_client.dart';

/// 单次多轮水平校准的结果
class MasteryCalibrationOutcome {
  final MasteryProfile profile;
  final bool levelChanged;
  final bool roadmapChanged;
  final String summaryNotice;

  const MasteryCalibrationOutcome({
    required this.profile,
    this.levelChanged = false,
    this.roadmapChanged = false,
    this.summaryNotice = '',
  });
}

/// 自适应精通引擎（水平诊断 + 动态学习路线图演化）
///
/// 职责：
/// 1. 开局规划：根据目标学科、学习目标与用户既有笔记/自述基础，生成 L1→L4 渐进路线图，并跳过已掌握节点；
/// 2. 多轮校准：每经过 2 轮问答或手动触发时，根据用户作答质量自动校准当前等级（L1~L4）、
///    记录强项与短板，并动态跳过已会内容或插入前置补漏关。
class MasteryCalibrator {
  const MasteryCalibrator();

  /// 每新增 4 条有效对话（2 轮问答）触发一次后台静默水平校准
  static const int autoCalibrateNewMessagesThreshold = 4;

  static final RegExp _masteryStartPattern = RegExp(
    r'(?:系统(?:地)?学(?:习)?|从(?:零|基础|入门|头).*?(?:精通|高级|专家|掌握)|(?:学到|练到|提升到).{0,6}(?:精通|高级|专家)|(?:制定|开启|规划).{0,10}(?:学习路线|精通路线|进阶路线))',
  );

  /// 判断用户发来的消息是否在明确请求“开启一门学科的从入门到精通系统路线”
  static bool looksLikeStartMasteryRequest(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return false;
    return _masteryStartPattern.hasMatch(text);
  }

  /// 判断是否到达后台自动校准时机
  bool shouldAutoCalibrate(
    List<StudyMessage> messages, {
    required MasteryProfile? activeProfile,
  }) {
    if (activeProfile == null) return false;
    final activeCount = messages.where((m) => !m.isCompactionNotice).length;
    return activeCount - activeProfile.lastCalibratedCount >=
        autoCalibrateNewMessagesThreshold;
  }

  static const String _roadmapSystemPrompt = '''
你是「回响」的通用自适应课程规划与水平诊断引擎，服务于任意学科、技能或专业（如编程、工程、金融、商业、管理、医学、法律、外语、人文艺术等）。只输出合法 JSON，不要任何 JSON 之外的解释文字。

## 核心方法论（高效达成专家，80/20 法则）
1. **因地制宜裁剪 80/20 主干**：不照搬百科全书目录，而是结合用户的具体应用场景与目标，提炼决定该领域 80% 实战能力的 20% 高杠杆核心心智模型，果断剪掉无关冷门支线。
2. **通用四阶能力阶梯（L1 → L4）**：
   - `beginner`（L1 入门）：破冰直觉，掌握核心因果如何运转、最小可运行闭环。
   - `intermediate`（L2 进阶）：规则边界与避坑，能分辨常规动作为何成立、换个条件为何失效。
   - `advanced`（L3 高级）：复杂推演与根因诊断，面对陌生异常场景或真实案例能独立推演根因并修复。
   - `expert`（L4 专家）：多目标权衡与跨场景迁移，面对没有唯一标准答案的冲突（如效率 vs 成本、短期 vs 长期、复杂度 vs 可靠性）能做出严谨取舍并降维讲透。
3. **跳过已知、直奔最短路径**：
   - `level` 仅限 `beginner` / `intermediate` / `advanced` / `expert`；`score` 为 `0~100`；`confidence` 为 `0.0~1.0`。
   - `roadmap` 包含 `8~12` 个覆盖 L1 → L4 的核心关隘。已有笔记或对话证明掌握的前置关隘直接标为 `"skipped"`（写明跳过依据），有且仅有 **1** 个当前主攻关隘标为 `"active"`。
   - `strengths` 与 `weaknesses` 各列 `0~4` 条极简短语（≤18字/条）。

严格按此 JSON 输出：
{
  "slug": "economics",
  "subject_name": "经济学与金融",
  "target_goal": "看懂公司财报并分析行业竞争格局",
  "level": "beginner",
  "score": 18,
  "confidence": 0.45,
  "strengths": ["供需与通胀基本直觉"],
  "weaknesses": ["现金流与利润混淆"],
  "roadmap": [
    {
      "id": "n1",
      "title": "供需关系与价格信号直觉",
      "level": "beginner",
      "status": "skipped",
      "focus_goal": "理解稀缺性与价格自发调节机制",
      "reason": "已有笔记显示已掌握"
    },
    {
      "id": "n2",
      "title": "利润 vs 现金流核心边界",
      "level": "beginner",
      "status": "active",
      "focus_goal": "分清账面盈利与真实造血能力，识别常见财务假象",
      "reason": "当前最关键的入门破冰关隘"
    }
  ]
}
''';

  static const String _calibrateSystemPrompt = '''
你是「回响」的通用多轮水平校准与动态调课引擎，服务于任意学科、技能或专业。只输出合法 JSON，不要输出多余文字。

## 校准铁律
1. 根据最近几轮用户的真实作答表现（是否独立推理、能否抓住因果本质、能否主动发现边界反例 vs 依赖提示、概念混淆、反复卡壳）动态调整：
   - **表现优秀且独立推导到位**：上调 `score` 与 `level`，把已打通节点标为 `"mastered"`；若展现出远超当前阶段的功底，把冗余低阶节点标为 `"skipped"` 并直接跃迁激活更高阶节点（`"active"`）。
   - **暴露前置底层盲区**：不必按部就班重学全部基础，只在当前 `active` 节点前动态插入 1 个极简前置补漏节点（`status: "active"`，`reason: "暴露短板补漏"`），原节点改回 `"pending"`。
   - **严格把关 L3 → L4（专家晋级通用铁律）**：进入 `advanced`（L3）后，若用户仅停留在概念口头复述，**不得**晋级为 `expert`（L4）；必须针对该领域的真实复杂情境完成“根因诊断 + 多目标权衡取舍 + 费曼级阐释”（编程类体现为代码排错或设计取舍，非编程类体现为真实案例拆解或决策权衡），才允许升至 `expert`。
2. 保证 `roadmap` 中最多只有 1 个 `"active"` 节点。
3. 若等级发生晋级、跳级或插入了补漏关，在 `notice_text` 中用一句话（≤36字）概括变化（否则留空串 `""`）。

严格按此 JSON 输出：
{
  "level": "intermediate",
  "score": 48,
  "confidence": 0.72,
  "strengths": ["核心因果清晰", "边界反例敏感"],
  "weaknesses": ["多目标冲突权衡"],
  "roadmap": [ ... 完整更新后的节点数组 ... ],
  "notice_text": "水平校准至 L2 进阶（48%），已跳过基础关并进入下一核心关隘"
}
''';

  Future<MasteryProfile> generateInitialRoadmap({
    required AiClient aiClient,
    required String subjectName,
    String? slug,
    String targetGoal = '',
    String existingDocMarkdown = '',
    List<StudyMessage> recentMessages = const [],
    int currentTotalConversationalCount = 0,
    DateTime? now,
  }) async {
    final payload = StringBuffer()
      ..writeln(
        '【目标学科】$subjectName${slug != null && slug.trim().isNotEmpty ? ' (slug: $slug)' : ''}',
      )
      ..writeln(
        '【用户学习目标】${targetGoal.trim().isNotEmpty ? targetGoal.trim() : '从当前真实水平一路学到高级/专家实战级'}',
      )
      ..writeln();

    if (existingDocMarkdown.trim().isNotEmpty) {
      payload
        ..writeln('【该专题已有沉淀笔记（可据此跳过已掌握基础）】')
        ..writeln(existingDocMarkdown.trim())
        ..writeln();
    }

    if (recentMessages.isNotEmpty) {
      final tail = recentMessages.length > 8
          ? recentMessages.sublist(recentMessages.length - 8)
          : recentMessages;
      payload.writeln('【近期对话记录（反映用户当前起点）】');
      for (final m in tail) {
        final speaker = m.role == StudyMessageRole.user ? '用户' : '回响';
        payload.writeln('$speaker：${m.content.trim()}');
      }
    }

    final raw = await aiClient.chat(
      [
        const AiMessage.system(_roadmapSystemPrompt),
        AiMessage.user(payload.toString()),
      ],
      enableWebSearch: false,
    );

    return parseRoadmapResponse(
      raw,
      slug: slug,
      subjectName: subjectName,
      targetGoal: targetGoal,
      lastCalibratedCount: currentTotalConversationalCount,
      now: now,
    );
  }

  MasteryProfile parseRoadmapResponse(
    String rawResponse, {
    String? slug,
    required String subjectName,
    String targetGoal = '',
    int lastCalibratedCount = 0,
    DateTime? now,
  }) {
    final map = _decodeJsonMap(rawResponse, errorLabel: '路线图生成');
    final resolvedSubject =
        (map['subject_name'] ?? '').toString().trim().isNotEmpty
            ? (map['subject_name'] ?? '').toString().trim()
            : subjectName.trim();
    final rawSlug = (slug != null && slug.trim().isNotEmpty)
        ? slug.trim()
        : ((map['slug'] ?? '').toString().trim().isNotEmpty
            ? (map['slug'] ?? '').toString().trim()
            : KnowledgeRepository.suggestSlug(resolvedSubject));
    final resolvedSlug = KnowledgeRepository.suggestSlug(rawSlug);

    final parsed = MasteryProfile.fromJson({
      ...map,
      'slug': resolvedSlug,
      'subject_name': resolvedSubject,
      if ((map['target_goal'] ?? '').toString().trim().isEmpty &&
          targetGoal.trim().isNotEmpty)
        'target_goal': targetGoal.trim(),
    });

    final normalizedRoadmap = _ensureSingleActiveNode(parsed.roadmap);
    return parsed.copyWith(
      slug: resolvedSlug,
      roadmap: normalizedRoadmap,
      lastCalibratedCount: lastCalibratedCount,
      updatedAt: now ?? DateTime.now(),
    );
  }

  Future<MasteryCalibrationOutcome> calibrateFromRecentTurns({
    required AiClient aiClient,
    required MasteryProfile currentProfile,
    required List<StudyMessage> recentMessages,
    String knowledgeDocMarkdown = '',
    required int currentTotalConversationalCount,
    DateTime? now,
  }) async {
    final tail = recentMessages.length > 8
        ? recentMessages.sublist(recentMessages.length - 8)
        : recentMessages;

    final payload = StringBuffer()
      ..writeln('【当前能力画像与路线图 JSON】')
      ..writeln(jsonEncode(currentProfile.toJson()))
      ..writeln();

    if (knowledgeDocMarkdown.trim().isNotEmpty) {
      payload
        ..writeln('【该专题当前已沉淀文档】')
        ..writeln(knowledgeDocMarkdown.trim())
        ..writeln();
    }

    payload.writeln('【最新对话片段（请据此评估真实水平并动态调课）】');
    for (final m in tail) {
      final speaker = m.role == StudyMessageRole.user ? '用户' : '回响';
      payload.writeln('$speaker：${m.content.trim()}');
    }

    final raw = await aiClient.chat(
      [
        const AiMessage.system(_calibrateSystemPrompt),
        AiMessage.user(payload.toString()),
      ],
      enableWebSearch: false,
    );

    return parseCalibrationResponse(
      raw,
      previous: currentProfile,
      currentTotalConversationalCount: currentTotalConversationalCount,
      now: now,
    );
  }

  MasteryCalibrationOutcome parseCalibrationResponse(
    String rawResponse, {
    required MasteryProfile previous,
    required int currentTotalConversationalCount,
    DateTime? now,
  }) {
    final map = _decodeJsonMap(rawResponse, errorLabel: '水平校准');
    final nextLevel = map['level'] != null
        ? MasteryLevel.fromString(map['level'].toString())
        : previous.level;
    final nextScore = map['score'] is num
        ? (map['score'] as num).toInt().clamp(0, 100)
        : previous.score;
    final nextConfidence = map['confidence'] is num
        ? (map['confidence'] as num).toDouble().clamp(0.0, 1.0)
        : previous.confidence;

    final nextStrengths = map['strengths'] is List
        ? (map['strengths'] as List)
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : previous.strengths;
    final nextWeaknesses = map['weaknesses'] is List
        ? (map['weaknesses'] as List)
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : previous.weaknesses;

    var nextRoadmap = previous.roadmap;
    if (map['roadmap'] is List) {
      final parsed = (map['roadmap'] as List)
          .whereType<Map>()
          .map((e) => RoadmapNode.fromJson(e.cast<String, dynamic>()))
          .where((n) => n.title.isNotEmpty)
          .toList();
      if (parsed.isNotEmpty) {
        nextRoadmap = _ensureSingleActiveNode(parsed);
      }
    }

    final updated = previous.copyWith(
      level: nextLevel,
      score: nextScore,
      confidence: nextConfidence,
      strengths: nextStrengths,
      weaknesses: nextWeaknesses,
      roadmap: nextRoadmap,
      lastCalibratedCount: currentTotalConversationalCount,
      updatedAt: now ?? DateTime.now(),
    );

    final levelChanged = updated.level != previous.level;
    final roadmapChanged =
        updated.activeNode?.id != previous.activeNode?.id ||
            updated.roadmap.length != previous.roadmap.length ||
            updated.completedNodesCount != previous.completedNodesCount;
    final rawNotice = (map['notice_text'] ?? '').toString().trim();

    return MasteryCalibrationOutcome(
      profile: updated,
      levelChanged: levelChanged,
      roadmapChanged: roadmapChanged,
      summaryNotice: rawNotice,
    );
  }

  List<RoadmapNode> _ensureSingleActiveNode(List<RoadmapNode> nodes) {
    if (nodes.isEmpty) return nodes;
    var foundActive = false;
    final result = <RoadmapNode>[];
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      final id = n.id.isNotEmpty ? n.id : 'node-${i + 1}';
      if (n.status == RoadmapNodeStatus.active) {
        if (!foundActive) {
          foundActive = true;
          result.add(n.copyWith(id: id));
        } else {
          result.add(n.copyWith(id: id, status: RoadmapNodeStatus.pending));
        }
      } else {
        result.add(n.copyWith(id: id));
      }
    }
    if (!foundActive) {
      final firstPending =
          result.indexWhere((n) => n.status == RoadmapNodeStatus.pending);
      if (firstPending >= 0) {
        result[firstPending] =
            result[firstPending].copyWith(status: RoadmapNodeStatus.active);
      }
    }
    return result;
  }

  Map<String, dynamic> _decodeJsonMap(
    String rawResponse, {
    required String errorLabel,
  }) {
    final trimmed = rawResponse.trim();
    final fenceMatch =
        RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
            .firstMatch(trimmed);
    final candidate = (fenceMatch?.group(1) ?? trimmed).trim();
    final firstBrace = candidate.indexOf('{');
    final lastBrace = candidate.lastIndexOf('}');
    if (firstBrace == -1 || lastBrace <= firstBrace) {
      throw FormatException('$errorLabel结果未能解析为 JSON');
    }
    final decoded = jsonDecode(candidate.substring(firstBrace, lastBrace + 1));
    if (decoded is! Map) {
      throw FormatException('$errorLabel结果根结构不是 JSON 对象');
    }
    return decoded.cast<String, dynamic>();
  }
}
