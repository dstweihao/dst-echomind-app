import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/ai/prompts/study_mode_prompt.dart';
import '../../data/ai/provider_presets.dart';
import '../../data/repositories/knowledge_exporter.dart';
import '../../data/repositories/knowledge_repository.dart';
import '../../domain/ai_enums_bridge.dart';
import '../../domain/models/knowledge_models.dart';
import '../../domain/models/update_status.dart';
import '../../providers.dart';
import '../../router.dart';
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/app_toast.dart';
import 'study_chat_controller.dart';
import 'widgets/knowledge_doc_sheet.dart';
import 'widgets/knowledge_drawer.dart';
import 'widgets/tts_status_pill.dart';
import 'widgets/voice_input_bar.dart';

class LearnPage extends ConsumerStatefulWidget {
  const LearnPage({super.key});

  @override
  ConsumerState<LearnPage> createState() => _LearnPageState();
}

class _LearnPageState extends ConsumerState<LearnPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(studyChatControllerProvider);
    final controller = ref.read(studyChatControllerProvider.notifier);
    final aiReady = ref.watch(aiAvailableProvider);
    final aiSettings = ref.watch(aiSettingsProvider);
    final updateStatus = ref.watch(updateStatusProvider);
    final availableUpdate =
        updateStatus is UpdateAvailable ? updateStatus : null;
    final voiceName =
        voiceOptionById(aiSettings.ttsVoiceId).name.split('·').first.trim();

    ref.listen<StudyChatState>(studyChatControllerProvider, (prev, next) {
      final msgAdded = next.messages.length != (prev?.messages.length ?? 0);
      final streamed =
          next.streamingText.length != (prev?.streamingText.length ?? 0);
      if (msgAdded || streamed) {
        _autoScroll();
      }
    });

    final canCompact = chatState.conversationalMessages.length >= 2 &&
        !chatState.isGenerating &&
        !chatState.isCompacting;

    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;

    final scaffold = Scaffold(
      backgroundColor: AppColors.background,
      drawer: KnowledgeDrawer(
        chatState: chatState,
        onOpenIndex: () {
          Navigator.of(context).pop();
          KnowledgeDocSheet.show(
            context,
            title: '知识沉淀总清单',
            subtitle: 'KNOWLEDGE.md',
            markdown: chatState.knowledgeIndex,
            onExportPressed: () => _exportSingleDoc(
              context,
              fileName: 'KNOWLEDGE.md',
              markdown: chatState.knowledgeIndex,
            ),
          );
        },
        onOpenDoc: (doc) async {
          Navigator.of(context).pop();
          await _openKnowledgeDocSheet(context, controller, doc);
        },
        onCompactNow: () {
          Navigator.of(context).pop();
          _triggerManualDistill(context, controller);
        },
        onCreateTopic: () {
          Navigator.of(context).pop();
          unawaited(_showCreateTopicDialog(context, controller));
        },
        onOrganizeWithAi: () {
          Navigator.of(context).pop();
          unawaited(_showOrganizeKnowledgeDialog(context, controller));
        },
        onExportAll: () {
          Navigator.of(context).pop();
          _exportKnowledgeBase(context);
        },
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(
              Icons.menu_book_rounded,
              size: 22,
              color: Color(0xFF1E293B),
            ),
            tooltip: '个人知识沉淀库 (KNOWLEDGE.md & docs/)',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text(
          AppIdentity.appName,
          style: TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              aiSettings.autoPlayTts
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              size: 21,
              color: aiSettings.autoPlayTts
                  ? AppColors.primary
                  : const Color(0xFF94A3B8),
            ),
            tooltip: aiSettings.autoPlayTts ? '自动语音播报已开启' : '自动语音播报已关闭',
            onPressed: () async {
              await controller.toggleAutoPlayTts();
              if (!context.mounted) return;
              final nextOn = !aiSettings.autoPlayTts;
              AppToast.showInfo(
                context,
                title: nextOn ? '已开启自动播报' : '已关闭自动播报',
              );
            },
          ),
          IconButton(
            icon: chatState.isCompacting
                ? SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Icon(
                    Icons.auto_awesome_rounded,
                    size: 20,
                    color: canCompact
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFCBD5E1),
                  ),
            tooltip: '沉淀到知识库（保留对话）',
            onPressed: canCompact
                ? () => _triggerManualDistill(context, controller)
                : null,
          ),
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 21,
                  color: Color(0xFF1E293B),
                ),
                if (availableUpdate != null)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      key: const Key('settings_update_dot'),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.background,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: availableUpdate != null
                ? '设置（发现新版本 ${availableUpdate.release.tagName}）'
                : '设置',
            onPressed: () => context.push(AppRouter.aiSettings),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!aiReady) _configBanner(context),
            if (chatState.statusBanner != null)
              _statusBanner(chatState.statusBanner!),
            if (chatState.focusedDocTitle != null)
              _focusedDocBar(
                chatState.focusedDocTitle!,
                chatState.focusedDocSlug ?? '',
                controller.clearFocusedDoc,
              ),
            Expanded(
              child: chatState.hasConversation
                  ? _buildConversation(chatState, controller)
                  : _buildWelcomeCenter(controller, chatState),
            ),
            if (chatState.errorMessage != null)
              _errorBar(chatState.errorMessage!, controller.clearError),
            TtsStatusPill(
              phase: chatState.ttsPhase,
              voiceName: voiceName,
              onStop: () => controller.stopPlayback(),
            ),
            VoiceInputBar(
              controller: _input,
              isGenerating: chatState.isGenerating,
              isParsingAttachment: chatState.isParsingAttachment,
              voicePhase: chatState.voicePhase,
              recordingAmplitude: chatState.recordingAmplitude,
              recordingDuration: chatState.recordingDuration,
              pendingAttachments: chatState.pendingAttachments,
              supportsCamera:
                  ref.read(attachmentPickerServiceProvider).supportsCamera,
              onSendText: () => _handleSend(controller),
              onCancelGeneration: () => controller.cancelGeneration(),
              onStartRecording: () => controller.startRecording(),
              onStopRecording: () => controller.stopRecordingAndTranscribe(
                onTranscribedForInput: (text) {
                  if (!mounted) return;
                  final current = _input.text.trim();
                  _input.text = current.isEmpty ? text : '$current $text';
                  _input.selection = TextSelection.fromPosition(
                    TextPosition(offset: _input.text.length),
                  );
                  setState(() {});
                },
              ),
              onCancelRecording: () => controller.cancelRecording(),
              onTextChanged: (_) => setState(() {}),
              onPickCamera: () => controller.pickCameraPhoto(),
              onPickGallery: () => controller.pickGalleryImages(),
              onPickFiles: () => controller.pickFiles(),
              onRemoveAttachment: controller.removePendingAttachment,
              onPasteFromClipboard: controller.pasteFromClipboard,
            ),
          ],
        ),
      ),
    );

    if (!isMac && !isWindows) return scaffold;

    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.keyV,
          meta: isMac,
          control: isWindows,
        ): () {
          unawaited(controller.pasteFromClipboard());
        },
      },
      child: Focus(
        autofocus: true,
        child: scaffold,
      ),
    );
  }

  Future<void> _triggerManualDistill(
    BuildContext context,
    StudyChatController controller,
  ) async {
    final count = await controller.distillNow();
    if (!context.mounted || count == null) return;
    if (count > 0) {
      AppToast.showSuccess(
        context,
        title: '已沉淀 $count 个知识点',
        detail: '已写入 KNOWLEDGE.md 与 docs/，对话记录已完整保留',
      );
    } else {
      AppToast.showInfo(
        context,
        title: '暂无可沉淀的新知识点',
        detail: '继续聊透一个概念后再试试吧',
      );
    }
  }

  Future<void> _showCreateTopicDialog(
    BuildContext context,
    StudyChatController controller,
  ) async {
    final existingSlugs = ref
        .read(studyChatControllerProvider)
        .knowledgeDocs
        .map((d) => d.slug)
        .toSet();

    final created = await showDialog<KnowledgeDocSummary>(
      context: context,
      builder: (_) => _CreateTopicDialog(
        existingSlugs: existingSlugs,
        onCreate: ({
          required String title,
          String? slug,
          String? markdown,
        }) =>
            controller.createTopic(
          title: title,
          slug: slug,
          markdown: markdown,
        ),
      ),
    );

    if (created == null || !context.mounted) return;
    AppToast.showSuccess(
      context,
      title: '已新建专题「${created.categoryName}」',
      detail: 'docs/${created.slug}.md',
    );
    await _openKnowledgeDocSheet(context, controller, created);
  }

  Future<void> _openKnowledgeDocSheet(
    BuildContext context,
    StudyChatController controller,
    KnowledgeDocSummary doc,
  ) async {
    final md = await controller.loadDocContent(doc.slug);
    if (!context.mounted) return;
    await KnowledgeDocSheet.show(
      context,
      title: doc.categoryName,
      subtitle: 'docs/${doc.slug}.md',
      markdown: md,
      onReviewPressed: () => controller.startReviewFromDoc(doc),
      onExportPressed: () async {
        final latest = await controller.loadDocContent(doc.slug);
        if (!context.mounted) return;
        await _exportSingleDoc(
          context,
          fileName: '${doc.slug}.md',
          markdown: latest,
        );
      },
      onSaveMarkdown: (updated) => controller.saveDocContent(
        slug: doc.slug,
        markdown: updated,
      ),
      onDeleteDoc: () => controller.deleteDoc(doc.slug),
    );
  }

  Future<void> _showOrganizeKnowledgeDialog(
    BuildContext context,
    StudyChatController controller,
  ) async {
    final instruction = await showDialog<String>(
      context: context,
      builder: (_) => const _OrganizeKnowledgeDialog(),
    );

    if (instruction == null || instruction.isEmpty || !context.mounted) return;
    final res = await controller.organizeKnowledgeBase(instruction);
    if (!context.mounted || res == null) return;
    AppToast.showSuccess(
      context,
      title: '知识库已整理',
      detail: res.summaryLine(),
    );
  }

  Rect? _shareOriginFor(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _exportKnowledgeBase(BuildContext context) async {
    final exporter = ref.read(knowledgeExporterProvider);
    final repo = ref.read(knowledgeRepositoryProvider);
    final result = await exporter.exportAll(
      repo,
      shareOrigin: _shareOriginFor(context),
    );
    if (!context.mounted) return;
    _showExportToast(context, result);
  }

  Future<void> _exportSingleDoc(
    BuildContext context, {
    required String fileName,
    required String markdown,
  }) async {
    final exporter = ref.read(knowledgeExporterProvider);
    final result = await exporter.exportMarkdown(
      fileName: fileName,
      markdown: markdown,
      shareOrigin: _shareOriginFor(context),
    );
    if (!context.mounted) return;
    _showExportToast(context, result);
  }

  void _showExportToast(BuildContext context, KnowledgeExportResult result) {
    switch (result.outcome) {
      case KnowledgeExportOutcome.saved:
        AppToast.showSuccess(
          context,
          title: '导出成功',
          detail: result.filePath != null
              ? '已保存 ${result.fileCount} 个文件至 ${result.filePath}'
              : '已保存 ${result.fileCount} 个文件',
        );
      case KnowledgeExportOutcome.shared:
        AppToast.showSuccess(
          context,
          title: '已导出知识库',
          detail: '共 ${result.fileCount} 个文件',
        );
      case KnowledgeExportOutcome.empty:
      case KnowledgeExportOutcome.failed:
        AppToast.showInfo(
          context,
          title: result.message.isNotEmpty ? result.message : '导出失败',
        );
      case KnowledgeExportOutcome.cancelled:
        break;
    }
  }

  void _handleSend(StudyChatController controller) {
    final text = _input.text.trim();
    final hasAttachments =
        ref.read(studyChatControllerProvider).pendingAttachments.isNotEmpty;
    if (text.isEmpty && !hasAttachments) return;
    _input.clear();
    setState(() {});
    unawaited(controller.sendText(text));
  }

  // ------------------------------------------------------------------
  // 欢迎中心（首次打开 / 单会话空态）
  // ------------------------------------------------------------------

  Widget _buildWelcomeCenter(
    StudyChatController controller,
    StudyChatState chatState,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const AppLogo(size: 42),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                '今天想聊点什么？',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              ...StudyModePrompt.starterPrompts.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => controller.sendText(item.prompt),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 13,
                            color: Color(0xFFCBD5E1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 单一长期对话流
  // ------------------------------------------------------------------

  Widget _buildConversation(
    StudyChatState chatState,
    StudyChatController controller,
  ) {
    final hasSummary = chatState.rollingSummary.trim().isNotEmpty;
    final visibleMessages = chatState.messages
        .where((m) => m.isCompactionNotice || m.role != StudyMessageRole.system)
        .toList(growable: false);
    final hasStreaming = chatState.streamingText.isNotEmpty;
    final hasThinking =
        chatState.isGenerating && chatState.streamingText.isEmpty;

    final totalCount = (hasSummary ? 1 : 0) +
        visibleMessages.length +
        (hasStreaming ? 1 : 0) +
        (hasThinking ? 1 : 0);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.sm,
      ),
      itemCount: totalCount,
      itemBuilder: (ctx, index) {
        var cursor = index;
        if (hasSummary) {
          if (cursor == 0) {
            return _RollingSummaryCard(summary: chatState.rollingSummary);
          }
          cursor--;
        }
        if (cursor < visibleMessages.length) {
          final msg = visibleMessages[cursor];
          if (msg.isCompactionNotice) {
            return _buildCompactionDivider(msg.content);
          }
          return _buildBubble(
            key: ValueKey(msg.id),
            msg: msg,
            isStreaming: false,
            isPlayingThis:
                chatState.isSpeaking && chatState.playingMessageId == msg.id,
            onToggleSpeak: () => controller.toggleMessagePlayback(msg),
          );
        }
        cursor -= visibleMessages.length;
        if (hasStreaming && cursor == 0) {
          return _buildBubble(
            key: const ValueKey(StudyChatController.streamingMessageId),
            msg: StudyMessage(
              id: StudyChatController.streamingMessageId,
              role: StudyMessageRole.assistant,
              content: chatState.streamingText,
              createdAt: DateTime.now(),
            ),
            isStreaming: true,
            isPlayingThis: chatState.isSpeaking &&
                chatState.playingMessageId ==
                    StudyChatController.streamingMessageId,
            onToggleSpeak: () => controller.stopPlayback(),
          );
        }
        return _buildThinkingIndicator();
      },
    );
  }

  Widget _buildCompactionDivider(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 13.5,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBubble({
    Key? key,
    required StudyMessage msg,
    required bool isStreaming,
    required bool isPlayingThis,
    required VoidCallback onToggleSpeak,
  }) {
    final isUser = msg.role == StudyMessageRole.user;

    String? thinking;
    String cleanContent = msg.content.trim();

    if (!isUser) {
      final thinkMatch =
          RegExp(r'<think>([\s\S]*?)<\/think>', caseSensitive: false)
              .firstMatch(cleanContent);
      if (thinkMatch != null) {
        thinking = thinkMatch.group(1)?.trim();
        cleanContent = cleanContent
            .replaceFirst(
              RegExp(r'<think>[\s\S]*?<\/think>', caseSensitive: false),
              '',
            )
            .trim();
      } else {
        final openMatch = RegExp(r'<think>([\s\S]*)$', caseSensitive: false)
            .firstMatch(cleanContent);
        if (openMatch != null) {
          thinking = openMatch.group(1)?.trim();
          cleanContent = '';
        }
      }
    }

    final needsKeyButton = !isUser &&
        (msg.content.contains('未配置 DeepSeek') ||
            msg.content.contains('尚未配置 DeepSeek') ||
            msg.content.contains('Key 无效') ||
            msg.content.contains('鉴权失败'));

    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.16),
                ),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(5),
              child: const AppLogo(size: 20),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 18),
                ),
                border: isUser
                    ? null
                    : Border.all(color: const Color(0xFFE2E8F0), width: 0.9),
                boxShadow: isUser
                    ? null
                    : [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (msg.attachments.isNotEmpty) ...[
                    _buildMessageAttachments(msg.attachments, isUser: isUser),
                    if (cleanContent.isNotEmpty) const SizedBox(height: 10),
                  ],
                  if (!isUser && thinking != null && thinking.isNotEmpty)
                    _ThinkingCard(
                      thinking: thinking,
                      isStreaming: isStreaming && cleanContent.isEmpty,
                    ),
                  if (cleanContent.isNotEmpty)
                    MarkdownBody(
                      data: cleanContent,
                      selectable: true,
                      styleSheet: _markdownStyle(isUser),
                    ),
                  if (!isUser && !isStreaming && cleanContent.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        InkWell(
                          onTap: onToggleSpeak,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isPlayingThis
                                      ? Icons.stop_circle_outlined
                                      : Icons.volume_up_outlined,
                                  size: 15,
                                  color: isPlayingThis
                                      ? AppColors.primary
                                      : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isPlayingThis ? '停止' : '朗读',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isPlayingThis
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isPlayingThis
                                        ? AppColors.primary
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: cleanContent));
                            AppToast.showCopied(context, message: '已复制内容到剪贴板');
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.copy_rounded,
                                  size: 14,
                                  color: Color(0xFF94A3B8),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '复制',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (needsKeyButton) ...[
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () => context.push(AppRouter.aiSettings),
                      icon: const Icon(Icons.key_rounded, size: 16),
                      label: const Text('前往设置 DeepSeek Key'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildMessageAttachments(
    List<StudyAttachment> attachments, {
    required bool isUser,
  }) {
    final images = attachments.where((a) => a.isImage).toList();
    final files = attachments.where((a) => a.isFile).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: images.map((img) {
              final f = File(img.localPath);
              final exists = img.localPath.isNotEmpty && f.existsSync();
              return GestureDetector(
                onTap: exists ? () => _showImagePreview(img.localPath, img.name) : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 112,
                    height: 112,
                    color: isUser
                        ? Colors.white.withValues(alpha: 0.16)
                        : const Color(0xFFF1F5F9),
                    child: exists
                        ? Image.file(f, fit: BoxFit.cover)
                        : Icon(
                            Icons.image_outlined,
                            color: isUser ? Colors.white70 : const Color(0xFF94A3B8),
                          ),
                  ),
                ),
              );
            }).toList(),
          ),
        if (images.isNotEmpty && files.isNotEmpty) const SizedBox(height: 8),
        if (files.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: files.map((file) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isUser
                      ? Colors.white.withValues(alpha: 0.18)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isUser
                        ? Colors.white.withValues(alpha: 0.25)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 15,
                      color: isUser ? Colors.white : AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: isUser ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  void _showImagePreview(String path, String title) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.file(File(path), fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(bool isUser) {
    return MarkdownStyleSheet(
      blockSpacing: 12.0,
      p: TextStyle(
        fontSize: 15.0,
        height: 1.65,
        color: isUser ? Colors.white : const Color(0xFF1E293B),
      ),
      strong: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15.0,
        color: isUser ? Colors.white : const Color(0xFF0F172A),
      ),
      code: TextStyle(
        fontSize: 13.5,
        color: isUser ? Colors.white : const Color(0xFF0F172A),
        backgroundColor: isUser
            ? Colors.white.withValues(alpha: 0.2)
            : const Color(0xFFF1F5F9),
        fontFamily: 'Menlo, Monaco, "Courier New", monospace',
      ),
      codeblockDecoration: BoxDecoration(
        color: isUser
            ? Colors.black.withValues(alpha: 0.2)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isUser
              ? Colors.white.withValues(alpha: 0.2)
              : const Color(0xFFE2E8F0),
        ),
      ),
      codeblockPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      blockquote: TextStyle(
        fontSize: 14.5,
        height: 1.6,
        color: isUser
            ? Colors.white.withValues(alpha: 0.9)
            : const Color(0xFF475569),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      blockquoteDecoration: BoxDecoration(
        color: isUser
            ? Colors.white.withValues(alpha: 0.12)
            : const Color(0xFFF8FAFC),
        border: Border(
          left: BorderSide(
            color: isUser ? Colors.white70 : AppColors.primary,
            width: 3.5,
          ),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      listBullet: TextStyle(
        color: isUser ? Colors.white : AppColors.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.16),
              ),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(5),
            child: const AppLogo(size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Text(
                  '思考中…',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 顶部辅助状态条
  // ------------------------------------------------------------------

  Widget _configBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.primary.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '未配置 DeepSeek Key',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
            ),
            onPressed: () => context.push(AppRouter.aiSettings),
            child: const Text('去配置', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _statusBanner(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: const Color(0xFFF0F9FF),
      child: Row(
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _focusedDocBar(String title, String slug, VoidCallback onClear) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Icon(Icons.folder_special_outlined, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '复习：$title',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF475569),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          InkWell(
            onTap: onClear,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 15, color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBar(String error, VoidCallback onDismiss) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.danger.withValues(alpha: 0.09),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 15, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(fontSize: 12.5, color: AppColors.danger),
            ),
          ),
          InkWell(
            onTap: onDismiss,
            child: Icon(Icons.close_rounded, size: 16, color: AppColors.danger),
          ),
        ],
      ),
    );
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }
}

class _RollingSummaryCard extends StatefulWidget {
  final String summary;

  const _RollingSummaryCard({required this.summary});

  @override
  State<_RollingSummaryCard> createState() => _RollingSummaryCardState();
}

class _RollingSummaryCardState extends State<_RollingSummaryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    Icons.memory_rounded,
                    size: 15,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '前文摘要',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: const Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.summary,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThinkingCard extends StatefulWidget {
  final String thinking;
  final bool isStreaming;

  const _ThinkingCard({
    required this.thinking,
    this.isStreaming = false,
  });

  @override
  State<_ThinkingCard> createState() => _ThinkingCardState();
}

class _ThinkingCardState extends State<_ThinkingCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isStreaming;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.thinking.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    widget.isStreaming
                        ? Icons.psychology_rounded
                        : Icons.lightbulb_outline_rounded,
                    size: 16,
                    color: const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isStreaming ? '正在深度思考…' : '已深度思考',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: const Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.thinking,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreateTopicDialog extends StatefulWidget {
  final Set<String> existingSlugs;
  final Future<KnowledgeDocSummary?> Function({
    required String title,
    String? slug,
    String? markdown,
  }) onCreate;

  const _CreateTopicDialog({
    required this.existingSlugs,
    required this.onCreate,
  });

  @override
  State<_CreateTopicDialog> createState() => _CreateTopicDialogState();
}

class _CreateTopicDialogState extends State<_CreateTopicDialog> {
  final _titleCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _slugManuallyEdited = false;
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _slugCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建知识专题'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('create_topic_title_input'),
              controller: _titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '专题名称',
                hintText: '例如：C++',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                if (!_slugManuallyEdited) {
                  _slugCtrl.text = val.trim().isEmpty
                      ? ''
                      : KnowledgeRepository.suggestSlug(
                          val,
                          existingSlugs: widget.existingSlugs,
                        );
                }
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('create_topic_slug_input'),
              controller: _slugCtrl,
              decoration: const InputDecoration(
                labelText: '文件名标识 (英文/数字，可留空自动生成)',
                hintText: '例如：cpp → docs/cpp.md',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                _slugManuallyEdited = val.trim().isNotEmpty;
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('create_topic_note_input'),
              controller: _noteCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '初始内容（可选，支持 Markdown）',
                hintText: '可留空，稍后随时编辑或让 AI 写入',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('create_topic_confirm_btn'),
          onPressed: (_submitting || _titleCtrl.text.trim().isEmpty)
              ? null
              : () async {
                  setState(() => _submitting = true);
                  final doc = await widget.onCreate(
                    title: _titleCtrl.text,
                    slug: _slugCtrl.text,
                    markdown: _noteCtrl.text,
                  );
                  if (!context.mounted) return;
                  Navigator.of(context).pop(doc);
                },
          child: const Text('创建'),
        ),
      ],
    );
  }
}

class _OrganizeKnowledgeDialog extends StatefulWidget {
  const _OrganizeKnowledgeDialog();

  @override
  State<_OrganizeKnowledgeDialog> createState() =>
      _OrganizeKnowledgeDialogState();
}

class _OrganizeKnowledgeDialogState extends State<_OrganizeKnowledgeDialog> {
  final _instrCtrl = TextEditingController();

  @override
  void dispose() {
    _instrCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 整理知识库'),
      content: TextField(
        key: const Key('organize_kb_instruction_input'),
        controller: _instrCtrl,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: '整理指令',
          hintText: '例如：把「编程与软件」里的 C++ 笔记拆成独立的「C++」专题',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('organize_kb_confirm_btn'),
          onPressed: _instrCtrl.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_instrCtrl.text.trim()),
          child: const Text('开始整理'),
        ),
      ],
    );
  }
}
