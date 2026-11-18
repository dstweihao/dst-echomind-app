import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_toast.dart';

/// 解析单条专题知识卡片（对应 `docs/<slug>.md` 中的每个 `## 主题` 段落）
class ParsedKnowledgeCard {
  final String topic;
  final String date;
  final String core;
  final String analogy;
  final String misconception;
  final String feynman;
  final List<String> extraLines;

  const ParsedKnowledgeCard({
    required this.topic,
    this.date = '',
    this.core = '',
    this.analogy = '',
    this.misconception = '',
    this.feynman = '',
    this.extraLines = const [],
  });

  bool get hasStructuredFields =>
      core.isNotEmpty ||
      analogy.isNotEmpty ||
      misconception.isNotEmpty ||
      feynman.isNotEmpty;

  static List<ParsedKnowledgeCard> parseFromMarkdown(String markdown) {
    final cards = <ParsedKnowledgeCard>[];
    String? topic;
    String date = '';
    String core = '';
    String analogy = '';
    String misconception = '';
    String feynman = '';
    var extras = <String>[];

    void flush() {
      if (topic == null || topic!.isEmpty) return;
      cards.add(
        ParsedKnowledgeCard(
          topic: topic!,
          date: date,
          core: core,
          analogy: analogy,
          misconception: misconception,
          feynman: feynman,
          extraLines: List<String>.unmodifiable(extras),
        ),
      );
      topic = null;
      date = '';
      core = '';
      analogy = '';
      misconception = '';
      feynman = '';
      extras = <String>[];
    }

    final datePattern = RegExp(r'\s*`(\d{4}-\d{2}-\d{2})`\s*$');

    for (final rawLine in markdown.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('# ') && topic == null) {
        // 顶部一级分类标题已展示在顶栏，跳过避免重复
        continue;
      }
      if (line.startsWith('## ')) {
        flush();
        final heading = line.substring(3).trim();
        final match = datePattern.firstMatch(heading);
        if (match != null) {
          date = match.group(1) ?? '';
          topic = heading.substring(0, match.start).trim();
        } else {
          topic = heading;
        }
        continue;
      }

      if (topic == null) continue;

      if (line.startsWith('- 核心：') || line.startsWith('- 核心:')) {
        core = line.replaceFirst(RegExp(r'^- 核心[：:]\s*'), '').trim();
      } else if (line.startsWith('- 类比：') || line.startsWith('- 类比:')) {
        analogy = line.replaceFirst(RegExp(r'^- 类比[：:]\s*'), '').trim();
      } else if (line.startsWith('- 误区：') || line.startsWith('- 误区:')) {
        misconception = line.replaceFirst(RegExp(r'^- 误区[：:]\s*'), '').trim();
      } else if (line.startsWith('- 复述：') || line.startsWith('- 复述:')) {
        feynman = line.replaceFirst(RegExp(r'^- 复述[：:]\s*'), '').trim();
      } else {
        extras.add(line);
      }
    }
    flush();

    return cards;
  }
}

/// 知识库全屏阅读页
///
/// - 专题文档（`docs/<slug>.md`）以结构化轻卡片展示，支持顶栏「遮住答案」闪卡自测（0 Token 回忆核对）；
/// - 总索引（`KNOWLEDGE.md`）及其他自由文档自动渲染为清爽 Markdown。
class KnowledgeDocSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String markdown;
  final VoidCallback? onReviewPressed;
  final VoidCallback? onExportPressed;

  const KnowledgeDocSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.markdown,
    this.onReviewPressed,
    this.onExportPressed,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String markdown,
    VoidCallback? onReviewPressed,
    VoidCallback? onExportPressed,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => KnowledgeDocSheet(
          title: title,
          subtitle: subtitle,
          markdown: markdown,
          onReviewPressed: onReviewPressed,
          onExportPressed: onExportPressed,
        ),
      ),
    );
  }

  @override
  State<KnowledgeDocSheet> createState() => _KnowledgeDocSheetState();
}

class _KnowledgeDocSheetState extends State<KnowledgeDocSheet> {
  late final List<ParsedKnowledgeCard> _cards =
      ParsedKnowledgeCard.parseFromMarkdown(widget.markdown);
  bool _selfTestMode = false;
  final Set<int> _revealedIndices = <int>{};

  bool get _useCardView =>
      _cards.isNotEmpty && _cards.every((c) => c.hasStructuredFields);

  void _toggleSelfTestMode() {
    setState(() {
      _selfTestMode = !_selfTestMode;
      _revealedIndices.clear();
    });
  }

  void _toggleRevealCard(int index) {
    if (!_selfTestMode) return;
    setState(() {
      if (_revealedIndices.contains(index)) {
        _revealedIndices.remove(index);
      } else {
        _revealedIndices.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _useCardView ? AppColors.background : AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 19,
            color: Color(0xFF1E293B),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            if (widget.subtitle.trim().isNotEmpty)
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                  fontFamily: 'Menlo, Monaco, monospace',
                ),
              ),
          ],
        ),
        actions: [
          if (_useCardView)
            IconButton(
              key: const Key('doc_self_test_toggle_btn'),
              tooltip: _selfTestMode ? '显示全部答案' : '遮住答案自测',
              icon: Icon(
                _selfTestMode
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_outlined,
                size: 20,
                color: _selfTestMode
                    ? AppColors.primary
                    : const Color(0xFF475569),
              ),
              onPressed: _toggleSelfTestMode,
            ),
          if (widget.onReviewPressed != null)
            IconButton(
              key: const Key('doc_review_btn'),
              tooltip: '复习这篇笔记',
              icon: Icon(
                Icons.school_outlined,
                size: 21,
                color: AppColors.primary,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onReviewPressed!();
              },
            ),
          if (widget.onExportPressed != null &&
              widget.markdown.trim().isNotEmpty)
            IconButton(
              key: const Key('doc_export_md_btn'),
              tooltip: '导出 Markdown',
              icon: const Icon(
                Icons.ios_share_rounded,
                size: 19.5,
                color: Color(0xFF475569),
              ),
              onPressed: widget.onExportPressed,
            ),
          IconButton(
            tooltip: '复制 Markdown',
            icon: const Icon(
              Icons.copy_rounded,
              size: 19,
              color: Color(0xFF475569),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.markdown));
              AppToast.showCopied(context, message: '已复制 Markdown');
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: _useCardView ? _buildCardsBody() : _buildMarkdownBody(),
        ),
      ),
    );
  }

  Widget _buildCardsBody() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
      itemCount: _cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final card = _cards[index];
        final isHidden = _selfTestMode && !_revealedIndices.contains(index);

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                key: Key('knowledge_card_$index'),
                onTap: _selfTestMode ? () => _toggleRevealCard(index) : null,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _selfTestMode && !isHidden
                          ? AppColors.primary.withValues(alpha: 0.35)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              card.topic,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                                height: 1.35,
                              ),
                            ),
                          ),
                          if (card.date.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Text(
                              card.date,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF94A3B8),
                                fontFamily: 'Menlo, Monaco, monospace',
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (isHidden)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                size: 15,
                                color: Color(0xFF94A3B8),
                              ),
                              SizedBox(width: 6),
                              Text(
                                '先自己回忆，点一下核对',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        if (card.core.isNotEmpty)
                          _fieldRow(
                            label: '核心',
                            text: card.core,
                            bg: const Color(0xFFEFF6FF),
                            fg: const Color(0xFF165DFF),
                          ),
                        if (card.analogy.isNotEmpty)
                          _fieldRow(
                            label: '类比',
                            text: card.analogy,
                            bg: const Color(0xFFECFEFF),
                            fg: const Color(0xFF0E7490),
                          ),
                        if (card.misconception.isNotEmpty)
                          _fieldRow(
                            label: '误区',
                            text: card.misconception,
                            bg: const Color(0xFFFEF2F2),
                            fg: const Color(0xFFDC2626),
                          ),
                        if (card.feynman.isNotEmpty)
                          _fieldRow(
                            label: '复述',
                            text: card.feynman,
                            bg: const Color(0xFFECFDF5),
                            fg: const Color(0xFF059669),
                            isLast: card.extraLines.isEmpty,
                          ),
                        if (card.extraLines.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: SelectableText(
                              card.extraLines.join('\n'),
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.6,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fieldRow({
    required String label,
    required String text,
    required Color bg,
    required Color fg,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.55,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkdownBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 36),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: MarkdownBody(
            data: widget.markdown.isEmpty ? '（暂无内容）' : widget.markdown,
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              blockSpacing: 12,
              h1: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
                height: 1.4,
              ),
              h2: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
                height: 1.45,
              ),
              h3: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
                height: 1.45,
              ),
              p: const TextStyle(
                fontSize: 15,
                height: 1.7,
                color: Color(0xFF334155),
              ),
              code: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF0F172A),
                backgroundColor: Color(0xFFF1F5F9),
                fontFamily: 'Menlo, Monaco, monospace',
              ),
              listBullet: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
