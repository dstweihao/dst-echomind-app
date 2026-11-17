import 'dart:async';

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

    return Scaffold(
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
          );
        },
        onOpenDoc: (doc) async {
          Navigator.of(context).pop();
          final md = await controller.loadDocContent(doc.slug);
          if (!context.mounted) return;
          await KnowledgeDocSheet.show(
            context,
            title: doc.categoryName,
            subtitle: 'docs/${doc.slug}.md',
            markdown: md,
            onReviewPressed: () => controller.startReviewFromDoc(doc),
          );
        },
        onCompactNow: () {
          Navigator.of(context).pop();
          _triggerManualCompaction(context, controller);
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
                    Icons.bookmark_add_outlined,
                    size: 20,
                    color: canCompact
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFCBD5E1),
                  ),
            tooltip: '沉淀并压缩',
            onPressed: canCompact
                ? () => _triggerManualCompaction(context, controller)
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
              voicePhase: chatState.voicePhase,
              recordingAmplitude: chatState.recordingAmplitude,
              recordingDuration: chatState.recordingDuration,
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
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerManualCompaction(
    BuildContext context,
    StudyChatController controller,
  ) async {
    final ok = await controller.compactAndDistillNow();
    if (!context.mounted || !ok) return;
    AppToast.showSuccess(
      context,
      title: '知识已沉淀',
      detail: '已更新 KNOWLEDGE.md 与 docs/ 并压缩上下文',
    );
  }

  void _handleSend(StudyChatController controller) {
    final text = _input.text.trim();
    if (text.isEmpty) return;
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
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.sm,
      ),
      children: [
        if (chatState.rollingSummary.trim().isNotEmpty)
          _RollingSummaryCard(summary: chatState.rollingSummary),
        for (final msg in chatState.messages)
          if (msg.isCompactionNotice)
            _buildCompactionDivider(msg.content)
          else if (msg.role != StudyMessageRole.system)
            _buildBubble(
              msg: msg,
              isStreaming: false,
              isPlayingThis:
                  chatState.isSpeaking && chatState.playingMessageId == msg.id,
              onToggleSpeak: () => controller.toggleMessagePlayback(msg),
            ),
        if (chatState.streamingText.isNotEmpty)
          _buildBubble(
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
          ),
        if (chatState.isGenerating && chatState.streamingText.isEmpty)
          _buildThinkingIndicator(),
      ],
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
                Icons.bookmark_added_outlined,
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
