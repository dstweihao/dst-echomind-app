import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_toast.dart';

/// 知识库全屏阅读页（撑满页面，右上角集成复习 / 导出 / 复制图标）
class KnowledgeDocSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
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
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            if (subtitle.trim().isNotEmpty)
              Text(
                subtitle,
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
          if (onReviewPressed != null)
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
                onReviewPressed!();
              },
            ),
          if (onExportPressed != null && markdown.trim().isNotEmpty)
            IconButton(
              key: const Key('doc_export_md_btn'),
              tooltip: '导出 Markdown',
              icon: const Icon(
                Icons.ios_share_rounded,
                size: 19.5,
                color: Color(0xFF475569),
              ),
              onPressed: onExportPressed,
            ),
          IconButton(
            tooltip: '复制 Markdown',
            icon: const Icon(
              Icons.copy_rounded,
              size: 19,
              color: Color(0xFF475569),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: markdown));
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 36),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: MarkdownBody(
                  data: markdown.isEmpty ? '（暂无内容）' : markdown,
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
          ),
        ),
      ),
    );
  }
}
