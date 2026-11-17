import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_toast.dart';

/// 知识沉淀 Markdown 阅读弹窗（支持阅读 `KNOWLEDGE.md` 或任意 `docs/<slug>.md`，并一键发起复习）
class KnowledgeDocSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final String markdown;
  final VoidCallback? onReviewPressed;

  const KnowledgeDocSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.markdown,
    this.onReviewPressed,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String markdown,
    VoidCallback? onReviewPressed,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => KnowledgeDocSheet(
        title: title,
        subtitle: subtitle,
        markdown: markdown,
        onReviewPressed: onReviewPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.84;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
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
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontFamily: 'Menlo, Monaco, monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '复制 Markdown',
                    icon: const Icon(
                      Icons.copy_rounded,
                      size: 19,
                      color: Color(0xFF64748B),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: markdown));
                      AppToast.showCopied(context, message: '已复制知识沉淀 Markdown');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: MarkdownBody(
                  data: markdown.isEmpty ? '（暂无内容）' : markdown,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    h1: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                    h2: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                    p: const TextStyle(
                      fontSize: 14.5,
                      height: 1.65,
                      color: Color(0xFF334155),
                    ),
                    listBullet: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            if (onReviewPressed != null) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onReviewPressed!();
                    },
                    icon: const Icon(Icons.psychology_alt_rounded, size: 19),
                    label: const Text('用苏格拉底方式复习这篇沉淀'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
