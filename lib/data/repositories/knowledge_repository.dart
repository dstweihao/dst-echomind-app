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

  /// 为任意中文/符号专题名推荐安全跨平台 ASCII 文件名 slug（如 `C++` → `cpp`）
  static String suggestSlug(
    String rawTitle, {
    Set<String>? existingSlugs,
  }) {
    final trimmed = rawTitle.trim();
    final aliased = trimmed
        .toLowerCase()
        .replaceAll('c++', 'cpp')
        .replaceAll('c#', 'csharp')
        .replaceAll('f#', 'fsharp')
        .replaceAll('.net', 'dotnet')
        .replaceAll('node.js', 'nodejs')
        .replaceAll('vue.js', 'vuejs');

    var base = KnowledgeEntry.normalizeSlug(aliased);
    final isExplicitGeneral = trimmed.toLowerCase() == 'general' ||
        trimmed == '通用' ||
        trimmed == '综合';

    if (base == 'general' && !isExplicitGeneral && trimmed.isNotEmpty) {
      // 纯非 ASCII 标题生成确定性短哈希 slug，避免不同中文专题挤进同一个 general.md
      var hash = 2166136261;
      for (final unit in trimmed.codeUnits) {
        hash ^= unit;
        hash = (hash * 16777619) & 0x7fffffff;
      }
      base = 'topic-${hash.toRadixString(36)}';
    }

    if (existingSlugs == null || !existingSlugs.contains(base)) {
      return base;
    }

    var idx = 2;
    while (existingSlugs.contains('$base-$idx')) {
      idx++;
    }
    return '$base-$idx';
  }

  /// 读取所有 `docs/*.md` 的全文内容，返回 `{slug: markdown}`
  Future<Map<String, String>> readAllDocsMarkdown() async {
    final docs = await listDocs();
    final result = <String, String>{};
    for (final doc in docs) {
      final raw = await readDocMarkdown(doc.slug);
      result[doc.slug] = raw;
    }
    return result;
  }

  /// 手动新建专题文档（`docs/<slug>.md`），并同步刷新 `KNOWLEDGE.md` 总清单
  Future<KnowledgeDocSummary> createTopic({
    required String title,
    String? slug,
    String? markdown,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', '专题名称不能为空');
    }

    final existingDocs = await listDocs();
    final existingSlugs = existingDocs.map((d) => d.slug).toSet();
    final safeSlug = (slug != null && slug.trim().isNotEmpty)
        ? KnowledgeEntry.normalizeSlug(slug)
        : suggestSlug(cleanTitle, existingSlugs: existingSlugs);

    final docPath = AppPaths.knowledgeDocFile(safeSlug);
    if (await _store.exists(docPath)) {
      throw StateError('专题「$safeSlug」已存在');
    }

    await _store.ensureDirectory(AppPaths.knowledgeDocsDir);

    final body = markdown?.trim() ?? '';
    final String finalContent;
    if (body.isEmpty) {
      finalContent = '# $cleanTitle\n';
    } else if (body.startsWith('# ')) {
      finalContent = '$body\n';
    } else {
      finalContent = '# $cleanTitle\n\n$body\n';
    }

    await _store.write(docPath, finalContent);
    await _rebuildIndex();

    final updated = await listDocs();
    return updated.firstWhere(
      (d) => d.slug == safeSlug,
      orElse: () => KnowledgeDocSummary(
        slug: safeSlug,
        categoryName: cleanTitle,
        filePath: docPath,
        topics: const [],
      ),
    );
  }

  /// 保存或覆写指定专题文档全文（`docs/<slug>.md`），并重建 `KNOWLEDGE.md`
  Future<void> saveDocMarkdown({
    required String slug,
    required String markdown,
  }) async {
    await applyUpdates(upserts: [(slug: slug, markdown: markdown)]);
  }

  /// 删除指定专题文档（`docs/<slug>.md`），并重建 `KNOWLEDGE.md`
  Future<void> deleteDoc(String slug) async {
    await applyUpdates(deletes: [slug]);
  }

  /// 批量写入/删除专题文档后统一重建一次 `KNOWLEDGE.md`
  Future<void> applyUpdates({
    List<({String slug, String markdown})> upserts = const [],
    List<String> deletes = const [],
  }) async {
    if (upserts.isEmpty && deletes.isEmpty) return;

    await _store.ensureDirectory(AppPaths.knowledgeDocsDir);

    for (final item in upserts) {
      final safeSlug = KnowledgeEntry.normalizeSlug(item.slug);
      final docPath = AppPaths.knowledgeDocFile(safeSlug);
      final trimmed = item.markdown.trimRight();
      await _store.write(docPath, trimmed.isEmpty ? '' : '$trimmed\n');
    }

    for (final slug in deletes) {
      final safeSlug = KnowledgeEntry.normalizeSlug(slug);
      final docPath = AppPaths.knowledgeDocFile(safeSlug);
      if (await _store.exists(docPath)) {
        await _store.delete(docPath);
      }
    }

    await _rebuildIndex();
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
