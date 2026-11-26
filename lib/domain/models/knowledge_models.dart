import '../ai_enums_bridge.dart';

enum StudyAttachmentKind { image, file }

/// 用户消息附带的图片或文档附件
class StudyAttachment {
  final String id;
  final StudyAttachmentKind kind;
  final String name;
  final String localPath;
  final String mimeType;
  final int sizeBytes;

  /// 文档类附件（纯文本直接读取，或 PDF/Word/PPT 经 DeepSeek OCR 提取）的纯文本内容
  final String? extractedText;

  const StudyAttachment({
    required this.id,
    required this.kind,
    required this.name,
    required this.localPath,
    required this.mimeType,
    this.sizeBytes = 0,
    this.extractedText,
  });

  bool get isImage => kind == StudyAttachmentKind.image;
  bool get isFile => kind == StudyAttachmentKind.file;

  StudyAttachment copyWith({
    String? extractedText,
  }) {
    return StudyAttachment(
      id: id,
      kind: kind,
      name: name,
      localPath: localPath,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      extractedText: extractedText ?? this.extractedText,
    );
  }

  factory StudyAttachment.fromJson(Map<String, dynamic> json) {
    final kindStr = (json['kind'] ?? 'file').toString();
    return StudyAttachment(
      id: (json['id'] ?? '').toString(),
      kind: kindStr == 'image'
          ? StudyAttachmentKind.image
          : StudyAttachmentKind.file,
      name: (json['name'] ?? '').toString(),
      localPath: (json['local_path'] ?? '').toString(),
      mimeType: (json['mime_type'] ?? 'application/octet-stream').toString(),
      sizeBytes: (json['size_bytes'] is num)
          ? (json['size_bytes'] as num).toInt()
          : 0,
      extractedText: json['extracted_text']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'local_path': localPath,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        if (extractedText != null && extractedText!.isNotEmpty)
          'extracted_text': extractedText,
      };
}

/// 单条学习对话消息
class StudyMessage {
  final String id;
  final StudyMessageRole role;
  final String content;
  final DateTime createdAt;

  /// 是否为“已沉淀压缩”系统视觉分隔卡（不作为普通对话发给大模型）
  final bool isCompactionNotice;

  /// 附带的图片或文档列表
  final List<StudyAttachment> attachments;

  const StudyMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isCompactionNotice = false,
    this.attachments = const [],
  });

  factory StudyMessage.fromJson(Map<String, dynamic> json) {
    final roleStr = (json['role'] ?? 'user').toString();
    final role = switch (roleStr) {
      'assistant' => StudyMessageRole.assistant,
      'system' => StudyMessageRole.system,
      _ => StudyMessageRole.user,
    };
    final rawAttachments = json['attachments'] as List<dynamic>? ?? const [];
    return StudyMessage(
      id: (json['id'] ?? '').toString(),
      role: role,
      content: (json['content'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      isCompactionNotice: json['is_compaction_notice'] == true,
      attachments: rawAttachments
          .whereType<Map>()
          .map((e) => StudyAttachment.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        if (isCompactionNotice) 'is_compaction_notice': true,
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
      };
}

/// 一条沉淀出的结构化知识卡片（追加写入 `docs/<categorySlug>.md` 并登记到 `KNOWLEDGE.md`）
class KnowledgeEntry {
  final String categorySlug;
  final String categoryName;
  final String topic;
  final String oneLiner;
  final String analogy;
  final String misconception;
  final String feynmanNote;
  final DateTime createdAt;

  const KnowledgeEntry({
    required this.categorySlug,
    required this.categoryName,
    required this.topic,
    required this.oneLiner,
    this.analogy = '',
    this.misconception = '',
    this.feynmanNote = '',
    required this.createdAt,
  });

  /// 规范化目录文件名 slug（纯 ASCII 小写字母、数字与连字符，跨平台安全）
  static String normalizeSlug(String raw) {
    final lower = raw.trim().toLowerCase();
    final cleaned = lower
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (cleaned.isEmpty) return 'general';
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  factory KnowledgeEntry.fromJson(
    Map<String, dynamic> json, {
    DateTime? now,
  }) {
    final slug = normalizeSlug((json['category_slug'] ?? 'general').toString());
    final catName = (json['category_name'] ?? '').toString().trim();
    return KnowledgeEntry(
      categorySlug: slug,
      categoryName: catName.isNotEmpty ? catName : slug,
      topic: (json['topic'] ?? '').toString().trim(),
      oneLiner: (json['one_liner'] ?? '').toString().trim(),
      analogy: (json['analogy'] ?? '').toString().trim(),
      misconception: (json['misconception'] ?? '').toString().trim(),
      feynmanNote: (json['feynman_note'] ?? '').toString().trim(),
      createdAt: now ?? DateTime.now(),
    );
  }
}

/// 专题文档摘要（供左侧「知识沉淀库」抽屉列表展示）
class KnowledgeDocSummary {
  final String slug;
  final String categoryName;
  final String filePath;
  final List<String> topics;
  final DateTime? updatedAt;

  const KnowledgeDocSummary({
    required this.slug,
    required this.categoryName,
    required this.filePath,
    required this.topics,
    this.updatedAt,
  });

  int get entryCount => topics.length;
}

/// 单次上下文压缩与沉淀的执行结果
class CompactionResult {
  final String rollingSummary;
  final List<KnowledgeEntry> entries;
  final int compactedMessageCount;

  const CompactionResult({
    required this.rollingSummary,
    required this.entries,
    required this.compactedMessageCount,
  });
}

/// 单一长期学习会话的本地工作记忆（落盘至 `conversation.json`）
class ConversationMemory {
  final String rollingSummary;
  final List<StudyMessage> messages;
  final String? focusedDocSlug;
  final String? activeMasterySlug;
  final String? contextWindowStartId;
  final int compactionCount;
  final int lastDistilledCount;
  final DateTime updatedAt;

  const ConversationMemory({
    this.rollingSummary = '',
    this.messages = const [],
    this.focusedDocSlug,
    this.activeMasterySlug,
    this.contextWindowStartId,
    this.compactionCount = 0,
    this.lastDistilledCount = 0,
    required this.updatedAt,
  });

  factory ConversationMemory.empty() =>
      ConversationMemory(updatedAt: DateTime.now());

  /// 实际参与大模型对话的有效消息（排除纯 UI 分隔提示卡）
  List<StudyMessage> get conversationalMessages =>
      messages.where((m) => !m.isCompactionNotice).toList();

  /// 活跃消息总字符数（用于上下文上限判断）
  int get activeCharCount => conversationalMessages.fold<int>(
        0,
        (sum, m) => sum + m.content.length,
      );

  ConversationMemory copyWith({
    String? rollingSummary,
    List<StudyMessage>? messages,
    String? focusedDocSlug,
    bool clearFocusedDoc = false,
    String? activeMasterySlug,
    bool clearActiveMastery = false,
    String? contextWindowStartId,
    bool clearContextWindowStart = false,
    int? compactionCount,
    int? lastDistilledCount,
    DateTime? updatedAt,
  }) {
    return ConversationMemory(
      rollingSummary: rollingSummary ?? this.rollingSummary,
      messages: messages ?? this.messages,
      focusedDocSlug:
          clearFocusedDoc ? null : (focusedDocSlug ?? this.focusedDocSlug),
      activeMasterySlug: clearActiveMastery
          ? null
          : (activeMasterySlug ?? this.activeMasterySlug),
      contextWindowStartId: clearContextWindowStart
          ? null
          : (contextWindowStartId ?? this.contextWindowStartId),
      compactionCount: compactionCount ?? this.compactionCount,
      lastDistilledCount: lastDistilledCount ?? this.lastDistilledCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ConversationMemory.fromJson(Map<String, dynamic> json) {
    final rawMsgs = (json['messages'] as List<dynamic>? ?? const []);
    final rawStartId = (json['context_window_start_id'] as String?)?.trim();
    final rawMastery = (json['active_mastery_slug'] as String?)?.trim();
    return ConversationMemory(
      rollingSummary: (json['rolling_summary'] ?? '').toString(),
      messages: rawMsgs
          .whereType<Map>()
          .map((e) => StudyMessage.fromJson(e.cast<String, dynamic>()))
          .toList(),
      focusedDocSlug: (json['focused_doc_slug'] as String?)?.trim().isNotEmpty ==
              true
          ? (json['focused_doc_slug'] as String).trim()
          : null,
      activeMasterySlug:
          (rawMastery != null && rawMastery.isNotEmpty) ? rawMastery : null,
      contextWindowStartId:
          (rawStartId != null && rawStartId.isNotEmpty) ? rawStartId : null,
      compactionCount: (json['compaction_count'] is num)
          ? (json['compaction_count'] as num).toInt()
          : 0,
      lastDistilledCount: (json['last_distilled_count'] is num)
          ? (json['last_distilled_count'] as num).toInt()
          : 0,
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'rolling_summary': rollingSummary,
        'messages': messages.map((m) => m.toJson()).toList(),
        if (focusedDocSlug != null && focusedDocSlug!.isNotEmpty)
          'focused_doc_slug': focusedDocSlug,
        if (activeMasterySlug != null && activeMasterySlug!.isNotEmpty)
          'active_mastery_slug': activeMasterySlug,
        if (contextWindowStartId != null && contextWindowStartId!.isNotEmpty)
          'context_window_start_id': contextWindowStartId,
        'compaction_count': compactionCount,
        'last_distilled_count': lastDistilledCount,
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// 学科精通等级（L1 入门 → L2 进阶 → L3 高级 → L4 专家）
enum MasteryLevel {
  beginner('L1 入门', 1),
  intermediate('L2 进阶', 2),
  advanced('L3 高级', 3),
  expert('L4 专家', 4);

  final String label;
  final int rank;

  const MasteryLevel(this.label, this.rank);

  static MasteryLevel fromString(String? raw) {
    final lower = (raw ?? '').trim().toLowerCase();
    return switch (lower) {
      'intermediate' || 'l2' => MasteryLevel.intermediate,
      'advanced' || 'l3' => MasteryLevel.advanced,
      'expert' || 'l4' => MasteryLevel.expert,
      _ => MasteryLevel.beginner,
    };
  }
}

/// 动态路线图节点状态
enum RoadmapNodeStatus {
  pending('待学'),
  active('当前聚焦'),
  mastered('已掌握'),
  skipped('已会跳过');

  final String label;

  const RoadmapNodeStatus(this.label);

  bool get isCompleted =>
      this == RoadmapNodeStatus.mastered || this == RoadmapNodeStatus.skipped;

  static RoadmapNodeStatus fromString(String? raw) {
    final lower = (raw ?? '').trim().toLowerCase();
    return switch (lower) {
      'active' => RoadmapNodeStatus.active,
      'mastered' => RoadmapNodeStatus.mastered,
      'skipped' => RoadmapNodeStatus.skipped,
      _ => RoadmapNodeStatus.pending,
    };
  }
}

/// 动态路线图中的单个知识关卡
class RoadmapNode {
  final String id;
  final String title;
  final MasteryLevel level;
  final RoadmapNodeStatus status;
  final String focusGoal;
  final String reason;

  const RoadmapNode({
    required this.id,
    required this.title,
    required this.level,
    this.status = RoadmapNodeStatus.pending,
    this.focusGoal = '',
    this.reason = '',
  });

  RoadmapNode copyWith({
    String? id,
    String? title,
    MasteryLevel? level,
    RoadmapNodeStatus? status,
    String? focusGoal,
    String? reason,
  }) {
    return RoadmapNode(
      id: id ?? this.id,
      title: title ?? this.title,
      level: level ?? this.level,
      status: status ?? this.status,
      focusGoal: focusGoal ?? this.focusGoal,
      reason: reason ?? this.reason,
    );
  }

  factory RoadmapNode.fromJson(Map<String, dynamic> json) {
    return RoadmapNode(
      id: (json['id'] ?? '').toString().trim(),
      title: (json['title'] ?? '').toString().trim(),
      level: MasteryLevel.fromString(json['level']?.toString()),
      status: RoadmapNodeStatus.fromString(json['status']?.toString()),
      focusGoal: (json['focus_goal'] ?? '').toString().trim(),
      reason: (json['reason'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'level': level.name,
        'status': status.name,
        if (focusGoal.isNotEmpty) 'focus_goal': focusGoal,
        if (reason.isNotEmpty) 'reason': reason,
      };
}

/// 单个学科/专题的自适应能力画像与动态路线图
class MasteryProfile {
  final String slug;
  final String subjectName;
  final String targetGoal;
  final MasteryLevel level;
  final int score;
  final double confidence;
  final List<String> strengths;
  final List<String> weaknesses;
  final List<RoadmapNode> roadmap;
  final int lastCalibratedCount;
  final DateTime updatedAt;

  const MasteryProfile({
    required this.slug,
    required this.subjectName,
    this.targetGoal = '',
    this.level = MasteryLevel.beginner,
    this.score = 0,
    this.confidence = 0.2,
    this.strengths = const [],
    this.weaknesses = const [],
    this.roadmap = const [],
    this.lastCalibratedCount = 0,
    required this.updatedAt,
  });

  RoadmapNode? get activeNode {
    for (final n in roadmap) {
      if (n.status == RoadmapNodeStatus.active) return n;
    }
    for (final n in roadmap) {
      if (n.status == RoadmapNodeStatus.pending) return n;
    }
    return null;
  }

  int get completedNodesCount =>
      roadmap.where((n) => n.status.isCompleted).length;

  double get roadmapProgress =>
      roadmap.isEmpty ? 0.0 : completedNodesCount / roadmap.length;

  MasteryProfile copyWith({
    String? slug,
    String? subjectName,
    String? targetGoal,
    MasteryLevel? level,
    int? score,
    double? confidence,
    List<String>? strengths,
    List<String>? weaknesses,
    List<RoadmapNode>? roadmap,
    int? lastCalibratedCount,
    DateTime? updatedAt,
  }) {
    return MasteryProfile(
      slug: slug ?? this.slug,
      subjectName: subjectName ?? this.subjectName,
      targetGoal: targetGoal ?? this.targetGoal,
      level: level ?? this.level,
      score: score ?? this.score,
      confidence: confidence ?? this.confidence,
      strengths: strengths ?? this.strengths,
      weaknesses: weaknesses ?? this.weaknesses,
      roadmap: roadmap ?? this.roadmap,
      lastCalibratedCount: lastCalibratedCount ?? this.lastCalibratedCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory MasteryProfile.fromJson(Map<String, dynamic> json) {
    final rawRoadmap = json['roadmap'] as List<dynamic>? ?? const [];
    final rawStrengths = json['strengths'] as List<dynamic>? ?? const [];
    final rawWeaknesses = json['weaknesses'] as List<dynamic>? ?? const [];
    return MasteryProfile(
      slug: KnowledgeEntry.normalizeSlug((json['slug'] ?? 'general').toString()),
      subjectName: (json['subject_name'] ?? '').toString().trim(),
      targetGoal: (json['target_goal'] ?? '').toString().trim(),
      level: MasteryLevel.fromString(json['level']?.toString()),
      score: (json['score'] is num)
          ? (json['score'] as num).toInt().clamp(0, 100)
          : 0,
      confidence: (json['confidence'] is num)
          ? (json['confidence'] as num).toDouble().clamp(0.0, 1.0)
          : 0.2,
      strengths: rawStrengths
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      weaknesses: rawWeaknesses
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      roadmap: rawRoadmap
          .whereType<Map>()
          .map((e) => RoadmapNode.fromJson(e.cast<String, dynamic>()))
          .where((n) => n.title.isNotEmpty)
          .toList(),
      lastCalibratedCount: (json['last_calibrated_count'] is num)
          ? (json['last_calibrated_count'] as num).toInt()
          : 0,
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'slug': slug,
        'subject_name': subjectName,
        if (targetGoal.isNotEmpty) 'target_goal': targetGoal,
        'level': level.name,
        'score': score,
        'confidence': confidence,
        'strengths': strengths,
        'weaknesses': weaknesses,
        'roadmap': roadmap.map((n) => n.toJson()).toList(),
        'last_calibrated_count': lastCalibratedCount,
        'updated_at': updatedAt.toIso8601String(),
      };
}
