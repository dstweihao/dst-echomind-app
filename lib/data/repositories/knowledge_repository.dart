import '../../domain/models/knowledge_models.dart';
import '../app_paths.dart';
import '../storage/file_store.dart';

/// Claude 式分层纯文本知识库仓库（`KNOWLEDGE.md` + `docs/<slug>.md`）
///
/// - `KNOWLEDGE.md`：总知识沉淀清单（自动注入系统提示词，体积精炼）。
/// - `docs/<slug>.md`：按类别/专题/行业持续增量追加的结构化 Markdown 笔记，永不覆盖旧内容。
class KnowledgeRepository {
  final FileStore _store;

  KnowledgeRepository(this._store);

  /// 读取总知识沉淀清单（`KNOWLEDGE.md`），不存在时返回空串
  Future<String> readIndexMarkdown() async {
    try {
      return (await _store.readOrNull(AppPaths.knowledgeIndexFile))?.trim() ??
          '';
    } catch (_) {
      return '';
    }
  }

  /// 读取指定专题文档全文（`docs/<slug>.md`）
  Future<String> readDocMarkdown(String slug) async {
    final safeSlug = KnowledgeEntry.normalizeSlug(slug);
    try {
      return (await _store.readOrNull(AppPaths.knowledgeDocFile(safeSlug)))
              ?.trim() ??
          '';
    } catch (_) {
      return '';
    }
  }

  /// 列出 `docs/` 目录下所有已沉淀的专题文档摘要
  Future<List<KnowledgeDocSummary>> listDocs() async {
    try {
      final exists = await _store.exists(AppPaths.knowledgeDocsDir);
      if (!exists) return const [];

      final entries = await _store.list(AppPaths.knowledgeDocsDir);
      final docs = <KnowledgeDocSummary>[];

      for (final entry in entries) {
        if (entry.isDirectory || !entry.name.toLowerCase().endsWith('.md')) {
          continue;
        }
        final slug = entry.name.substring(0, entry.name.length - 3);
        final content = await _store.readOrNull(entry.path) ?? '';
        final parsed = _parseDocMeta(slug, entry.path, content, entry.lastModified);
        docs.add(parsed);
      }

      docs.sort((a, b) {
        final at = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return docs;
    } catch (_) {
      return const [];
    }
  }

  /// 将一批新沉淀的知识卡片增量写入对应 `docs/<slug>.md`，并同步重建 `KNOWLEDGE.md` 总清单
  Future<void> appendEntries(List<KnowledgeEntry> entries) async {
    final valid = entries
        .where((e) => e.topic.trim().isNotEmpty && e.oneLiner.trim().isNotEmpty)
        .toList();
    if (valid.isEmpty) return;

    await _store.ensureDirectory(AppPaths.knowledgeDocsDir);

    // 按类别分组增量追加到对应 docs/<slug>.md
    final bySlug = <String, List<KnowledgeEntry>>{};
    for (final item in valid) {
      final slug = KnowledgeEntry.normalizeSlug(item.categorySlug);
      bySlug.putIfAbsent(slug, () => []).add(item);
    }

    for (final pair in bySlug.entries) {
      final slug = pair.key;
      final group = pair.value;
      final docPath = AppPaths.knowledgeDocFile(slug);
      final existing = await _store.readOrNull(docPath);

      final buf = StringBuffer();
      if (existing == null || existing.trim().isEmpty) {
        buf.writeln('# ${group.first.categoryName}');
        buf.writeln();
      } else {
        buf.writeln(existing.trimRight());
        buf.writeln();
      }

      for (final e in group) {
        buf.write(_formatEntryBlock(e));
      }

      await _store.write(docPath, '${buf.toString().trimRight()}\n');
    }

    await _rebuildIndex();
  }

  /// 扫描所有 `docs/*.md` 重建精炼总清单 `KNOWLEDGE.md`（永不漂移、自动去重）
  Future<void> _rebuildIndex() async {
    final docs = await listDocs();
    if (docs.isEmpty) {
      if (await _store.exists(AppPaths.knowledgeIndexFile)) {
        await _store.delete(AppPaths.knowledgeIndexFile);
      }
      return;
    }

    final buf = StringBuffer()
      ..writeln('# KNOWLEDGE.md')
      ..writeln();

    for (final doc in docs) {
      final raw = await readDocMarkdown(doc.slug);
      final items = _extractIndexItems(raw);
      buf.writeln('## ${doc.categoryName} (`docs/${doc.slug}.md`)');
      if (items.isNotEmpty) {
        // 同名主题保留最新一条沉淀的一句话总结
        final dedup = <String, String>{};
        for (final it in items) {
          dedup[it.$1] = it.$2;
        }
        for (final entry in dedup.entries) {
          buf.writeln('- **${entry.key}**：${entry.value}');
        }
      }
      buf.writeln();
    }

    await _store.write(AppPaths.knowledgeIndexFile, '${buf.toString().trimRight()}\n');
  }

  String _formatEntryBlock(KnowledgeEntry e) {
    final date =
        '${e.createdAt.year}-${e.createdAt.month.toString().padLeft(2, '0')}-${e.createdAt.day.toString().padLeft(2, '0')}';
    final buf = StringBuffer()
      ..writeln('## ${e.topic} `$date`')
      ..writeln('- 核心：${e.oneLiner}');
    if (e.analogy.isNotEmpty) {
      buf.writeln('- 类比：${e.analogy}');
    }
    if (e.misconception.isNotEmpty) {
      buf.writeln('- 误区：${e.misconception}');
    }
    if (e.feynmanNote.isNotEmpty) {
      buf.writeln('- 复述：${e.feynmanNote}');
    }
    buf.writeln();
    return buf.toString();
  }

  KnowledgeDocSummary _parseDocMeta(
    String slug,
    String path,
    String content,
    DateTime? updatedAt,
  ) {
    String categoryName = slug;
    final topics = <String>[];

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.startsWith('# ') && categoryName == slug) {
        final title = line.substring(2).trim();
        if (title.isNotEmpty) categoryName = title;
      } else if (line.startsWith('## ')) {
        final topic = _stripHeadingDate(line.substring(3).trim());
        if (topic.isNotEmpty && !topics.contains(topic)) {
          topics.add(topic);
        }
      }
    }

    return KnowledgeDocSummary(
      slug: slug,
      categoryName: categoryName,
      filePath: path,
      topics: topics,
      updatedAt: updatedAt,
    );
  }

  List<(String, String)> _extractIndexItems(String docMarkdown) {
    final result = <(String, String)>[];
    String? currentTopic;

    for (final rawLine in docMarkdown.split('\n')) {
      final line = rawLine.trim();
      if (line.startsWith('## ')) {
        currentTopic = _stripHeadingDate(line.substring(3).trim());
      } else if (currentTopic != null && line.startsWith('- 核心：')) {
        final oneLiner = line.substring('- 核心：'.length).trim();
        if (oneLiner.isNotEmpty) {
          result.add((currentTopic, oneLiner));
          currentTopic = null;
        }
      }
    }
    return result;
  }

  String _stripHeadingDate(String heading) {
    return heading.replaceFirst(RegExp(r'\s*`\d{4}-\d{2}-\d{2}`\s*$'), '').trim();
  }
}
