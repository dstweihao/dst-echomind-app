import 'dart:async';

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

  bool matchesQuery(String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return topic.toLowerCase().contains(q) ||
        core.toLowerCase().contains(q) ||
        analogy.toLowerCase().contains(q) ||
        misconception.toLowerCase().contains(q) ||
        feynman.toLowerCase().contains(q) ||
        extraLines.any((l) => l.toLowerCase().contains(q));
  }

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
/// 顶栏收束为 3 个清晰入口：`[ 🔍 大纲与搜索 ]  [ 复习 / 退出自测 ]  [ ⋯ 更多 ]`。
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
  late final List<GlobalKey> _cardKeys =
      List.generate(_cards.length, (_) => GlobalKey());

  bool _selfTestMode = false;
  final Set<int> _revealedIndices = <int>{};
  int? _highlightedIndex;
  Timer? _highlightTimer;

  bool get _useCardView =>
      _cards.isNotEmpty && _cards.every((c) => c.hasStructuredFields);

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _enterSelfTestMode() {
    setState(() {
      _selfTestMode = true;
      _revealedIndices.clear();
    });
  }

  void _exitSelfTestMode() {
    setState(() {
      _selfTestMode = false;
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

  void _scrollToCard(int index) {
    if (index < 0 || index >= _cardKeys.length) return;
    final ctx = _cardKeys[index].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.06,
      );
    }
    _highlightTimer?.cancel();
    setState(() => _highlightedIndex = index);
    _highlightTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _highlightedIndex = null);
    });
  }

  Future<void> _openOutlineSearchSheet() async {
    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OutlineSearchSheet(cards: _cards),
    );
    if (selectedIndex != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCard(selectedIndex);
      });
    }
  }

  Future<void> _openReviewMenu() async {
    if (_selfTestMode) {
      _exitSelfTestMode();
      return;
    }

    if (!_useCardView && widget.onReviewPressed != null) {
      Navigator.of(context).pop();
      widget.onReviewPressed!();
      return;
    }

    if (_useCardView && widget.onReviewPressed == null) {
      _enterSelfTestMode();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                _reviewOptionTile(
                  key: const Key('review_option_self_test'),
                  icon: Icons.visibility_off_outlined,
                  title: '遮住答案自测',
                  subtitle: '0 消耗，先回忆再点卡片核对',
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _enterSelfTestMode();
                  },
                ),
                const SizedBox(height: 10),
                _reviewOptionTile(
                  key: const Key('review_option_ai_socratic'),
                  icon: Icons.school_outlined,
                  title: 'AI 苏格拉底抽查',
                  subtitle: '回到对话，由回响反问考你',
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    Navigator.of(context).pop();
                    widget.onReviewPressed!();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reviewOptionTile({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showReviewButton = _useCardView || widget.onReviewPressed != null;

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
              key: const Key('doc_outline_search_btn'),
              tooltip: '大纲与搜索',
              icon: const Icon(
                Icons.search_rounded,
                size: 21,
                color: Color(0xFF334155),
              ),
              onPressed: _openOutlineSearchSheet,
            ),
          if (showReviewButton)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Center(
                child: InkWell(
                  key: Key(
                    _selfTestMode
                        ? 'doc_exit_self_test_btn'
                        : 'doc_review_menu_btn',
                  ),
                  onTap: _openReviewMenu,
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _selfTestMode
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _selfTestMode ? '退出自测' : '复习',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _selfTestMode ? Colors.white : AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          PopupMenuButton<String>(
            key: const Key('doc_more_menu_btn'),
            tooltip: '更多',
            icon: const Icon(
              Icons.more_horiz_rounded,
              size: 21,
              color: Color(0xFF475569),
            ),
            color: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            onSelected: (action) {
              if (action == 'export') {
                widget.onExportPressed?.call();
              } else if (action == 'copy') {
                Clipboard.setData(ClipboardData(text: widget.markdown));
                AppToast.showCopied(context, message: '已复制 Markdown');
              }
            },
            itemBuilder: (context) => [
              if (widget.onExportPressed != null &&
                  widget.markdown.trim().isNotEmpty)
                const PopupMenuItem<String>(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(
                        Icons.ios_share_rounded,
                        size: 18,
                        color: Color(0xFF475569),
                      ),
                      SizedBox(width: 10),
                      Text('导出 Markdown', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              const PopupMenuItem<String>(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(
                      Icons.copy_rounded,
                      size: 17,
                      color: Color(0xFF475569),
                    ),
                    SizedBox(width: 10),
                    Text('复制 Markdown', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ],
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              for (var index = 0; index < _cards.length; index++) ...[
                if (index > 0) const SizedBox(height: 12),
                _buildCardItem(index),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardItem(int index) {
    final card = _cards[index];
    final isHidden = _selfTestMode && !_revealedIndices.contains(index);
    final isHighlighted = _highlightedIndex == index;

    return Material(
      key: _cardKeys[index],
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: Key('knowledge_card_$index'),
        onTap: _selfTestMode ? () => _toggleRevealCard(index) : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              width: isHighlighted ? 1.6 : 1,
              color: isHighlighted
                  ? AppColors.primary
                  : (_selfTestMode && !isHidden
                      ? AppColors.primary.withValues(alpha: 0.35)
                      : const Color(0xFFE2E8F0)),
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
                    border: Border.all(color: const Color(0xFFE2E8F0)),
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

/// 大纲 + 即时搜索合二为一的轻量面板
class _OutlineSearchSheet extends StatefulWidget {
  final List<ParsedKnowledgeCard> cards;

  const _OutlineSearchSheet({required this.cards});

  @override
  State<_OutlineSearchSheet> createState() => _OutlineSearchSheetState();
}

class _OutlineSearchSheetState extends State<_OutlineSearchSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.74;
    final matched = <(int, ParsedKnowledgeCard)>[];
    for (var i = 0; i < widget.cards.length; i++) {
      if (widget.cards[i].matchesQuery(_query)) {
        matched.add((i, widget.cards[i]));
      }
    }

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: TextField(
                    key: const Key('doc_outline_search_input'),
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(fontSize: 14.5),
                    decoration: InputDecoration(
                      hintText: '搜索知识点、类比或误区…',
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF94A3B8),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: Color(0xFF64748B),
                      ),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Color(0xFF94A3B8),
                              ),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: Row(
                    children: [
                      Text(
                        _query.trim().isEmpty
                            ? '大纲 · 共 ${widget.cards.length} 条'
                            : '匹配 ${matched.length} / ${widget.cards.length} 条',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                Flexible(
                  child: matched.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: Text(
                            '没有匹配的知识点',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        )
                      : ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: matched.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              indent: 18,
                              color: Color(0xFFF1F5F9),
                            ),
                            itemBuilder: (context, idx) {
                              final (origIndex, card) = matched[idx];
                              final order =
                                  (origIndex + 1).toString().padLeft(2, '0');
                              return ListTile(
                                key: Key('outline_item_$origIndex'),
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 2,
                                ),
                                leading: Text(
                                  order,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF94A3B8),
                                    fontFamily: 'Menlo, Monaco, monospace',
                                  ),
                                ),
                                minLeadingWidth: 22,
                                title: Text(
                                  card.topic,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                subtitle: card.core.isNotEmpty
                                    ? Text(
                                        card.core,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
                                        ),
                                      )
                                    : null,
                                trailing: card.date.isNotEmpty
                                    ? Text(
                                        card.date,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF94A3B8),
                                          fontFamily:
                                              'Menlo, Monaco, monospace',
                                        ),
                                      )
                                    : null,
                                onTap: () =>
                                    Navigator.of(context).pop(origIndex),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
