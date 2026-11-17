import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/knowledge_models.dart';
import '../../../shared/widgets/app_logo.dart';
import '../study_chat_controller.dart';

/// 左侧抽屉：Claude 式个人知识沉淀库（`KNOWLEDGE.md` 总清单 + `docs/<专题>.md` 分类沉淀）
class KnowledgeDrawer extends StatelessWidget {
  final StudyChatState chatState;
  final VoidCallback onOpenIndex;
  final ValueChanged<KnowledgeDocSummary> onOpenDoc;
  final VoidCallback onCompactNow;

  const KnowledgeDrawer({
    super.key,
    required this.chatState,
    required this.onOpenIndex,
    required this.onOpenDoc,
    required this.onCompactNow,
  });

  @override
  Widget build(BuildContext context) {
    final docs = chatState.knowledgeDocs;
    final hasIndex = chatState.knowledgeIndex.trim().isNotEmpty;

    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 10),
              child: Row(
                children: [
                  const AppLogo(size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    '知识库',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 总清单入口：KNOWLEDGE.md（对标 CLAUDE.md）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
              child: InkWell(
                onTap: hasIndex ? onOpenIndex : null,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.description_outlined,
                          size: 20,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'KNOWLEDGE.md',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                                fontFamily: 'Menlo, Monaco, monospace',
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              hasIndex
                                  ? '${docs.length} 专题 · ${chatState.totalKnowledgeTopics} 条'
                                  : '暂无沉淀',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasIndex)
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: AppColors.primary,
                        ),
                    ],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Text(
                    '专题',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const Spacer(),
                  if (chatState.conversationalMessages.length >= 2)
                    TextButton.icon(
                      onPressed: chatState.isCompacting ? null : onCompactNow,
                      icon: const Icon(Icons.bookmark_add_outlined, size: 15),
                      label: const Text('沉淀'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            Expanded(
              child: docs.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无沉淀内容',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: docs.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 16),
                      itemBuilder: (ctx, i) {
                        final doc = docs[i];
                        final isFocused = chatState.focusedDocSlug == doc.slug;
                        return ListTile(
                          selected: isFocused,
                          selectedTileColor:
                              AppColors.primary.withValues(alpha: 0.08),
                          leading: Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isFocused
                                  ? AppColors.primary.withValues(alpha: 0.14)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.folder_outlined,
                              size: 18,
                              color: isFocused
                                  ? AppColors.primary
                                  : const Color(0xFF64748B),
                            ),
                          ),
                          title: Text(
                            doc.categoryName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isFocused
                                  ? AppColors.primary
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                          subtitle: Text(
                            '${doc.entryCount} 条',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Color(0xFF94A3B8),
                          ),
                          onTap: () => onOpenDoc(doc),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
