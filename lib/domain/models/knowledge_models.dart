import '../ai_enums_bridge.dart';

/// 单条学习对话消息
class StudyMessage {
  final String id;
  final StudyMessageRole role;
  final String content;
  final DateTime createdAt;

  /// 是否为“已沉淀压缩”系统视觉分隔卡（不作为普通对话发给大模型）
  final bool isCompactionNotice;

  const StudyMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isCompactionNotice = false,
  });

  factory StudyMessage.fromJson(Map<String, dynamic> json) {
    final roleStr = (json['role'] ?? 'user').toString();
    final role = switch (roleStr) {
      'assistant' => StudyMessageRole.assistant,
      'system' => StudyMessageRole.system,
      _ => StudyMessageRole.user,
    };
    return StudyMessage(
      id: (json['id'] ?? '').toString(),
      role: role,
      content: (json['content'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      isCompactionNotice: json['is_compaction_notice'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        if (isCompactionNotice) 'is_compaction_notice': true,
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
  final int compactionCount;
  final int lastDistilledCount;
  final DateTime updatedAt;

  const ConversationMemory({
    this.rollingSummary = '',
    this.messages = const [],
    this.focusedDocSlug,
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
    int? compactionCount,
    int? lastDistilledCount,
    DateTime? updatedAt,
  }) {
    return ConversationMemory(
      rollingSummary: rollingSummary ?? this.rollingSummary,
      messages: messages ?? this.messages,
      focusedDocSlug:
          clearFocusedDoc ? null : (focusedDocSlug ?? this.focusedDocSlug),
      compactionCount: compactionCount ?? this.compactionCount,
      lastDistilledCount: lastDistilledCount ?? this.lastDistilledCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ConversationMemory.fromJson(Map<String, dynamic> json) {
    final rawMsgs = (json['messages'] as List<dynamic>? ?? const []);
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
        'compaction_count': compactionCount,
        'last_distilled_count': lastDistilledCount,
        'updated_at': updatedAt.toIso8601String(),
      };
}
