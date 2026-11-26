import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ai/ai_client.dart';
import '../../data/ai/context_compactor.dart';
import '../../data/ai/deepseek_ocr_client.dart';
import '../../data/ai/knowledge_organizer.dart';
import '../../data/ai/mastery_calibrator.dart';
import '../../data/ai/prompts/study_mode_prompt.dart';
import '../../data/ai/sensitive_content_guard.dart';
import '../../data/attachments/attachment_picker_service.dart';
import '../../data/voice/deepseek_asr_client.dart';
import '../../data/voice/deepseek_tts_client.dart';
import '../../data/voice/wav_encoder.dart';
import '../../domain/ai_enums_bridge.dart';
import '../../domain/models/knowledge_models.dart';
import '../../providers.dart';

enum VoiceInputPhase { idle, recording, transcribing }

enum TtsPlaybackPhase { idle, connecting, playing }

class StudyChatState {
  /// 单一长期会话中的活跃消息（含压缩分隔提示卡）
  final List<StudyMessage> messages;

  /// 上下文压缩后的前文工作记忆摘要
  final String rollingSummary;

  /// 总知识沉淀清单（KNOWLEDGE.md 原文）
  final String knowledgeIndex;

  /// docs/ 目录下的全部专题知识文档摘要
  final List<KnowledgeDocSummary> knowledgeDocs;

  /// 若用户从知识库点选某专题进行苏格拉底复习，记录该专题 slug 与内容
  final String? focusedDocSlug;
  final String? focusedDocTitle;
  final String? focusedDocContent;

  /// 各学科的隐式精通能力画像（完全无感，后台持续评估校准）
  final Map<String, MasteryProfile> masteryProfiles;
  final String? activeMasterySlug;

  /// 发给大模型的滑动窗口起点消息 ID（该标记之后才进入 wireMessages，之前消息保留在界面但不再耗费上下文）
  final String? contextWindowStartId;

  final int compactionCount;
  final int lastDistilledCount;
  final bool isCompacting;
  final String streamingText;
  final bool isGenerating;
  final VoiceInputPhase voicePhase;
  final double recordingAmplitude;
  final Duration recordingDuration;
  final TtsPlaybackPhase ttsPhase;
  final String? playingMessageId;
  final List<StudyAttachment> pendingAttachments;
  final bool isParsingAttachment;
  final String? errorMessage;
  final String? statusBanner;
  final bool hydrated;

  const StudyChatState({
    this.messages = const [],
    this.rollingSummary = '',
    this.knowledgeIndex = '',
    this.knowledgeDocs = const [],
    this.focusedDocSlug,
    this.focusedDocTitle,
    this.focusedDocContent,
    this.masteryProfiles = const {},
    this.activeMasterySlug,
    this.contextWindowStartId,
    this.compactionCount = 0,
    this.lastDistilledCount = 0,
    this.isCompacting = false,
    this.streamingText = '',
    this.isGenerating = false,
    this.voicePhase = VoiceInputPhase.idle,
    this.recordingAmplitude = 0.0,
    this.recordingDuration = Duration.zero,
    this.ttsPhase = TtsPlaybackPhase.idle,
    this.playingMessageId,
    this.pendingAttachments = const [],
    this.isParsingAttachment = false,
    this.errorMessage,
    this.statusBanner,
    this.hydrated = false,
  });

  bool get isSpeaking => ttsPhase != TtsPlaybackPhase.idle;
  bool get isRecording => voicePhase == VoiceInputPhase.recording;
  bool get isTranscribing => voicePhase == VoiceInputPhase.transcribing;
  bool get hasConversation => messages.isNotEmpty || streamingText.isNotEmpty;

  /// 界面展示与总对话计数用的有效对话消息
  List<StudyMessage> get conversationalMessages =>
      messages.where((m) => !m.isCompactionNotice).toList();

  /// 实际发给大模型 API 的活跃上下文窗口（已归纳进前文摘要的历史不再重复发原文）
  List<StudyMessage> get activeLlmMessages {
    final startId = contextWindowStartId;
    if (startId == null || startId.isEmpty) {
      return conversationalMessages;
    }
    final idx = messages.indexWhere((m) => m.id == startId);
    if (idx == -1) {
      return conversationalMessages;
    }
    return messages
        .sublist(idx + 1)
        .where((m) => !m.isCompactionNotice)
        .toList();
  }

  /// 当前激活的学科精通画像（供后台静默评估与分阶引导，不在 UI 造成打扰）
  MasteryProfile? get activeMastery {
    final slug = activeMasterySlug;
    if (slug == null || slug.isEmpty) return null;
    return masteryProfiles[slug];
  }

  /// 总已沉淀知识点条数
  int get totalKnowledgeTopics =>
      knowledgeDocs.fold<int>(0, (sum, d) => sum + d.entryCount);

  StudyChatState copyWith({
    List<StudyMessage>? messages,
    String? rollingSummary,
    String? knowledgeIndex,
    List<KnowledgeDocSummary>? knowledgeDocs,
    String? focusedDocSlug,
    String? focusedDocTitle,
    String? focusedDocContent,
    bool clearFocusedDoc = false,
    Map<String, MasteryProfile>? masteryProfiles,
    String? activeMasterySlug,
    bool clearActiveMastery = false,
    String? contextWindowStartId,
    bool clearContextWindowStart = false,
    int? compactionCount,
    int? lastDistilledCount,
    bool? isCompacting,
    String? streamingText,
    bool? isGenerating,
    VoiceInputPhase? voicePhase,
    double? recordingAmplitude,
    Duration? recordingDuration,
    TtsPlaybackPhase? ttsPhase,
    String? playingMessageId,
    bool clearPlayingMessageId = false,
    List<StudyAttachment>? pendingAttachments,
    bool? isParsingAttachment,
    String? errorMessage,
    bool clearError = false,
    String? statusBanner,
    bool clearStatusBanner = false,
    bool? hydrated,
  }) {
    return StudyChatState(
      messages: messages ?? this.messages,
      rollingSummary: rollingSummary ?? this.rollingSummary,
      knowledgeIndex: knowledgeIndex ?? this.knowledgeIndex,
      knowledgeDocs: knowledgeDocs ?? this.knowledgeDocs,
      focusedDocSlug:
          clearFocusedDoc ? null : (focusedDocSlug ?? this.focusedDocSlug),
      focusedDocTitle:
          clearFocusedDoc ? null : (focusedDocTitle ?? this.focusedDocTitle),
      focusedDocContent: clearFocusedDoc
          ? null
          : (focusedDocContent ?? this.focusedDocContent),
      masteryProfiles: masteryProfiles ?? this.masteryProfiles,
      activeMasterySlug: clearActiveMastery
          ? null
          : (activeMasterySlug ?? this.activeMasterySlug),
      contextWindowStartId: clearContextWindowStart
          ? null
          : (contextWindowStartId ?? this.contextWindowStartId),
      compactionCount: compactionCount ?? this.compactionCount,
      lastDistilledCount: lastDistilledCount ?? this.lastDistilledCount,
      isCompacting: isCompacting ?? this.isCompacting,
      streamingText: streamingText ?? this.streamingText,
      isGenerating: isGenerating ?? this.isGenerating,
      voicePhase: voicePhase ?? this.voicePhase,
      recordingAmplitude: recordingAmplitude ?? this.recordingAmplitude,
      recordingDuration: recordingDuration ?? this.recordingDuration,
      ttsPhase: ttsPhase ?? this.ttsPhase,
      playingMessageId: clearPlayingMessageId
          ? null
          : (playingMessageId ?? this.playingMessageId),
      pendingAttachments: pendingAttachments ?? this.pendingAttachments,
      isParsingAttachment: isParsingAttachment ?? this.isParsingAttachment,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      statusBanner:
          clearStatusBanner ? null : (statusBanner ?? this.statusBanner),
      hydrated: hydrated ?? this.hydrated,
    );
  }
}

final studyChatControllerProvider =
    NotifierProvider<StudyChatController, StudyChatState>(
  StudyChatController.new,
);

/// 单一长期学习会话 + Claude 式知识沉淀（KNOWLEDGE.md + docs/*.md）+ DeepSeek 语音全栈编排器
class StudyChatController extends Notifier<StudyChatState> {
  static const String streamingMessageId = '__streaming__';

  StreamSubscription<AiChunk>? _llmSub;
  StreamSubscription<double>? _ampSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<Uint8List>? _ttsAudioSub;

  DeepSeekTtsStreamSession? _activeTtsSession;
  int _playbackToken = 0;
  int _recordingToken = 0;

  @override
  StudyChatState build() {
    ref.onDispose(_cleanupAll);
    Future.microtask(_hydrate);
    return const StudyChatState();
  }

  Future<void> _hydrate() async {
    final convRepo = ref.read(conversationRepositoryProvider);
    final kbRepo = ref.read(knowledgeRepositoryProvider);
    final masteryRepo = ref.read(masteryRepositoryProvider);

    final memory = await convRepo.load();
    final indexMd = await kbRepo.readIndexMarkdown();
    final docs = await kbRepo.listDocs();
    final profiles = await masteryRepo.loadAllProfiles();

    String? focusedTitle;
    String? focusedBody;
    if (memory.focusedDocSlug != null) {
      final matched =
          docs.where((d) => d.slug == memory.focusedDocSlug).firstOrNull;
      if (matched != null) {
        focusedTitle = matched.categoryName;
        focusedBody = await kbRepo.readDocMarkdown(matched.slug);
      }
    }

    final resolvedMasterySlug =
        state.activeMasterySlug ?? memory.activeMasterySlug;

    if (!ref.mounted) return;
    state = state.copyWith(
      messages: state.messages.isEmpty ? memory.messages : state.messages,
      rollingSummary: state.rollingSummary.isEmpty
          ? memory.rollingSummary
          : state.rollingSummary,
      knowledgeIndex: indexMd,
      knowledgeDocs: docs,
      focusedDocSlug: focusedTitle != null ? memory.focusedDocSlug : null,
      focusedDocTitle: focusedTitle,
      focusedDocContent: focusedBody,
      masteryProfiles: profiles,
      activeMasterySlug:
          (resolvedMasterySlug != null && profiles.containsKey(resolvedMasterySlug))
              ? resolvedMasterySlug
              : null,
      contextWindowStartId:
          state.contextWindowStartId ?? memory.contextWindowStartId,
      compactionCount: memory.compactionCount,
      lastDistilledCount: memory.lastDistilledCount,
      hydrated: true,
    );
  }

  // ------------------------------------------------------------------
  // 知识沉淀库交互（KNOWLEDGE.md + docs/<slug>.md）
  // ------------------------------------------------------------------

  /// 刷新知识库索引与 docs 列表
  Future<void> refreshKnowledgeBase() async {
    final kbRepo = ref.read(knowledgeRepositoryProvider);
    final indexMd = await kbRepo.readIndexMarkdown();
    final docs = await kbRepo.listDocs();
    if (!ref.mounted) return;
    state = state.copyWith(
      knowledgeIndex: indexMd,
      knowledgeDocs: docs,
    );
  }

  /// 读取某篇专题文档全文
  Future<String> loadDocContent(String slug) {
    return ref.read(knowledgeRepositoryProvider).readDocMarkdown(slug);
  }

  /// 从知识库某专题发起苏格拉底复习：按需挂载 `docs/<slug>.md` 并发起首轮追问
  Future<void> startReviewFromDoc(KnowledgeDocSummary doc) async {
    final body = await loadDocContent(doc.slug);
    if (!ref.mounted) return;
    state = state.copyWith(
      focusedDocSlug: doc.slug,
      focusedDocTitle: doc.categoryName,
      focusedDocContent: body,
      activeMasterySlug:
          state.masteryProfiles.containsKey(doc.slug) ? doc.slug : null,
      clearError: true,
    );
    await _persistMemory();

    await sendText(
      '我想复习「${doc.categoryName}」里沉淀的内容，请挑其中一个容易忘或有意思的点，用苏格拉底方式考考我。',
    );
  }

  /// 后台静默生成或加载指定学科的自适应精通画像（完全无感，不向 UI 抛噪音）
  Future<void> _ensureMasteryProfileSilently(
    String rawRequest,
    AiClient client,
  ) async {
    try {
      final kbRepo = ref.read(knowledgeRepositoryProvider);
      final masteryRepo = ref.read(masteryRepositoryProvider);
      final calibrator = ref.read(masteryCalibratorProvider);

      // 优先匹配已有的专题文档（如 docs/cpp.md）以便继承历史沉淀笔记
      final lowerReq = rawRequest.toLowerCase();
      KnowledgeDocSummary? matchedDoc;
      for (final d in state.knowledgeDocs) {
        if (lowerReq.contains(d.categoryName.toLowerCase()) ||
            lowerReq.contains(d.slug.toLowerCase())) {
          matchedDoc = d;
          break;
        }
      }

      if (matchedDoc != null && state.masteryProfiles.containsKey(matchedDoc.slug)) {
        state = state.copyWith(activeMasterySlug: matchedDoc.slug);
        await _persistMemory();
        return;
      }

      final existingMd = matchedDoc != null
          ? await kbRepo.readDocMarkdown(matchedDoc.slug)
          : '';
      final profile = await calibrator.generateInitialRoadmap(
        aiClient: client,
        subjectName: matchedDoc?.categoryName ?? rawRequest,
        slug: matchedDoc?.slug,
        targetGoal: rawRequest,
        existingDocMarkdown: existingMd,
        recentMessages: state.conversationalMessages,
        currentTotalConversationalCount:
            (state.conversationalMessages.length - 1).clamp(0, 1 << 30),
      );
      if (!ref.mounted) return;

      await masteryRepo.saveProfile(profile);
      final nextMap = Map<String, MasteryProfile>.from(state.masteryProfiles);
      nextMap[profile.slug] = profile;
      state = state.copyWith(
        masteryProfiles: nextMap,
        activeMasterySlug: profile.slug,
      );
      await _persistMemory();
    } catch (e) {
      debugPrint('Silent mastery initialization skipped: $e');
    }
  }

  /// 后台静默每 2 轮校准一次用户当前水平与路线图（完全无感）
  Future<void> _calibrateMasteryQuietlyInBackground() async {
    final active = state.activeMastery;
    if (active == null || state.isGenerating) return;
    final client = ref.read(aiClientProvider);
    if (client == null) return;

    final conv = state.conversationalMessages;
    final calibrator = ref.read(masteryCalibratorProvider);
    if (!calibrator.shouldAutoCalibrate(
      state.messages,
      activeProfile: active,
    )) {
      return;
    }

    try {
      final kbRepo = ref.read(knowledgeRepositoryProvider);
      final masteryRepo = ref.read(masteryRepositoryProvider);
      final docMd = await kbRepo.readDocMarkdown(active.slug);

      final outcome = await calibrator.calibrateFromRecentTurns(
        aiClient: client,
        currentProfile: active,
        recentMessages: conv,
        knowledgeDocMarkdown: docMd,
        currentTotalConversationalCount: conv.length,
      );
      if (!ref.mounted) return;

      await masteryRepo.saveProfile(outcome.profile);
      final nextMap = Map<String, MasteryProfile>.from(state.masteryProfiles);
      nextMap[outcome.profile.slug] = outcome.profile;
      state = state.copyWith(masteryProfiles: nextMap);
    } catch (e) {
      debugPrint('Silent mastery calibration skipped: $e');
    }
  }

  /// 取消当前挂载的专题复习上下文
  Future<void> clearFocusedDoc() async {
    if (state.focusedDocSlug == null) return;
    state = state.copyWith(clearFocusedDoc: true);
    await _persistMemory();
  }

  /// 手动新建知识库专题
  Future<KnowledgeDocSummary?> createTopic({
    required String title,
    String? slug,
    String? markdown,
  }) async {
    try {
      final kbRepo = ref.read(knowledgeRepositoryProvider);
      final created = await kbRepo.createTopic(
        title: title,
        slug: slug,
        markdown: markdown,
      );
      await refreshKnowledgeBase();
      return created;
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
          errorMessage: e is StateError ? e.message : '新建专题失败：$e',
        );
      }
      return null;
    }
  }

  /// 手动保存专题文档全文并同步刷新索引
  Future<bool> saveDocContent({
    required String slug,
    required String markdown,
  }) async {
    try {
      final kbRepo = ref.read(knowledgeRepositoryProvider);
      await kbRepo.saveDocMarkdown(slug: slug, markdown: markdown);
      final updatedIndex = await kbRepo.readIndexMarkdown();
      final updatedDocs = await kbRepo.listDocs();
      if (!ref.mounted) return false;

      final safeSlug = KnowledgeEntry.normalizeSlug(slug);
      final isFocused = state.focusedDocSlug == safeSlug;
      final matched = updatedDocs.where((d) => d.slug == safeSlug).firstOrNull;
      final refreshedBody =
          isFocused ? await kbRepo.readDocMarkdown(safeSlug) : null;
      if (!ref.mounted) return false;

      state = state.copyWith(
        knowledgeIndex: updatedIndex,
        knowledgeDocs: updatedDocs,
        focusedDocTitle: isFocused ? matched?.categoryName : null,
        focusedDocContent: isFocused ? refreshedBody : null,
      );
      return true;
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(errorMessage: '保存专题失败：$e');
      }
      return false;
    }
  }

  /// 手动删除专题文档并同步刷新索引
  Future<bool> deleteDoc(String slug) async {
    try {
      final kbRepo = ref.read(knowledgeRepositoryProvider);
      final safeSlug = KnowledgeEntry.normalizeSlug(slug);
      await kbRepo.deleteDoc(safeSlug);
      final updatedIndex = await kbRepo.readIndexMarkdown();
      final updatedDocs = await kbRepo.listDocs();
      if (!ref.mounted) return false;

      final wasFocused = state.focusedDocSlug == safeSlug;
      state = state.copyWith(
        knowledgeIndex: updatedIndex,
        knowledgeDocs: updatedDocs,
        clearFocusedDoc: wasFocused,
      );
      if (wasFocused) {
        await _persistMemory();
      }
      return true;
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(errorMessage: '删除专题失败：$e');
      }
      return false;
    }
  }

  /// 通过 AI 直接执行知识库专题新增、拆分或整理落盘
  Future<KnowledgeOrganizeResult?> organizeKnowledgeBase(
    String instruction, {
    bool appendAssistantReply = true,
  }) async {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty) return null;

    final client = ref.read(aiClientProvider);
    if (client == null) {
      state = state.copyWith(errorMessage: '请先配置 DeepSeek API Key 以整理知识库');
      return null;
    }

    state = state.copyWith(
      isGenerating: true,
      clearError: true,
      statusBanner: '正在整理知识库专题…',
    );

    try {
      final result = await _executeKnowledgeOrganize(
        instruction: trimmed,
        client: client,
        appendAssistantReply: appendAssistantReply,
      );
      return result;
    } catch (e) {
      if (!ref.mounted) return null;
      state = state.copyWith(
        isGenerating: false,
        clearStatusBanner: true,
        errorMessage: '整理知识库失败：$e',
      );
      return null;
    }
  }

  Future<KnowledgeOrganizeResult> _executeKnowledgeOrganize({
    required String instruction,
    required AiClient client,
    required bool appendAssistantReply,
  }) async {
    final kbRepo = ref.read(knowledgeRepositoryProvider);
    final convRepo = ref.read(conversationRepositoryProvider);
    final organizer = ref.read(knowledgeOrganizerProvider);

    final allDocs = await kbRepo.readAllDocsMarkdown();
    final currentIndex = await kbRepo.readIndexMarkdown();

    final plan = await organizer.plan(
      aiClient: client,
      instruction: instruction,
      knowledgeIndex: currentIndex,
      allDocs: allDocs,
      recentMessages: state.conversationalMessages,
    );

    final result = await organizer.applyPlan(
      repository: kbRepo,
      plan: plan,
    );

    final updatedIndex = await kbRepo.readIndexMarkdown();
    final updatedDocs = await kbRepo.listDocs();
    if (!ref.mounted) return result;

    String? refreshedTitle;
    String? refreshedBody;
    var clearFocused = false;
    final focusedSlug = state.focusedDocSlug;
    if (focusedSlug != null) {
      if (result.deletedSlugs.contains(focusedSlug)) {
        clearFocused = true;
      } else if (result.touchedSlugs.contains(focusedSlug)) {
        final matched =
            updatedDocs.where((d) => d.slug == focusedSlug).firstOrNull;
        refreshedTitle = matched?.categoryName;
        refreshedBody = await kbRepo.readDocMarkdown(focusedSlug);
      }
    }

    if (!ref.mounted) return result;

    state = state.copyWith(
      isGenerating: false,
      clearStatusBanner: true,
      knowledgeIndex: updatedIndex,
      knowledgeDocs: updatedDocs,
      focusedDocTitle: refreshedTitle,
      focusedDocContent: refreshedBody,
      clearFocusedDoc: clearFocused,
    );

    final toAppend = <StudyMessage>[];
    if (result.touchedSlugs.isNotEmpty || result.deletedSlugs.isNotEmpty) {
      toAppend.add(
        StudyMessage(
          id: convRepo.nextMessageId(),
          role: StudyMessageRole.system,
          content: result.summaryLine(),
          createdAt: DateTime.now(),
          isCompactionNotice: true,
        ),
      );
    }

    StudyMessage? replyMsg;
    if (appendAssistantReply && result.reply.isNotEmpty) {
      replyMsg = StudyMessage(
        id: convRepo.nextMessageId(),
        role: StudyMessageRole.assistant,
        content: result.reply,
        createdAt: DateTime.now(),
      );
      toAppend.add(replyMsg);
    }

    if (toAppend.isNotEmpty) {
      await _appendMessages(toAppend);
    }

    if (replyMsg != null) {
      final settings = ref.read(aiSettingsProvider);
      final ttsClient = ref.read(deepSeekTtsClientProvider);
      if (settings.autoPlayTts && ttsClient != null) {
        unawaited(
          _playViaHttp(
            text: replyMsg.content,
            messageId: replyMsg.id,
            voiceId: settings.ttsVoiceId,
          ),
        );
      }
    }

    return result;
  }

  /// 手动一键「沉淀知识」（仅提炼知识点写入 `KNOWLEDGE.md` 与 `docs/`，完整保留对话框里的全部历史记录）
  Future<int?> distillNow() async {
    if (state.isCompacting || state.isGenerating) return null;

    final active = state.conversationalMessages;
    if (active.length < 2) {
      state = state.copyWith(errorMessage: '至少先聊完 1 轮再做知识沉淀哦');
      return null;
    }

    final client = ref.read(aiClientProvider);
    if (client == null) {
      state = state.copyWith(errorMessage: '请先配置 DeepSeek API Key 以执行知识沉淀');
      return null;
    }

    final startIdx = state.lastDistilledCount < active.length
        ? state.lastDistilledCount
        : (active.length > 6 ? active.length - 6 : 0);
    final slice = active.sublist(startIdx);
    final newWatermark = active.length;

    state = state.copyWith(
      isCompacting: true,
      clearError: true,
      statusBanner: '正在提炼知识点到 KNOWLEDGE.md 与 docs/…',
    );

    try {
      final compactor = ref.read(contextCompactorProvider);
      final result = await compactor.compact(
        aiClient: client,
        previousSummary: state.rollingSummary,
        existingKnowledgeIndex: state.knowledgeIndex,
        messagesToCompact: slice,
      );
      if (!ref.mounted) return null;

      final kbRepo = ref.read(knowledgeRepositoryProvider);
      if (result.entries.isNotEmpty) {
        await kbRepo.appendEntries(result.entries);
      }
      final updatedIndex = await kbRepo.readIndexMarkdown();
      final updatedDocs = await kbRepo.listDocs();

      state = state.copyWith(
        knowledgeIndex: updatedIndex,
        knowledgeDocs: updatedDocs,
        lastDistilledCount: newWatermark,
        isCompacting: false,
        clearStatusBanner: true,
      );

      await _persistMemory();
      return result.entries.length;
    } catch (e) {
      debugPrint('Distill failed: $e');
      if (!ref.mounted) return null;
      state = state.copyWith(
        isCompacting: false,
        clearStatusBanner: true,
        errorMessage: '沉淀失败，原对话已完整保留：$e',
      );
      return null;
    }
  }

  /// 归纳工作记忆摘要并推进大模型滑动窗口（完整保留界面上的历史气泡不删减）
  Future<bool> compactAndDistillNow({bool isAuto = false}) async {
    if (state.isCompacting || state.isGenerating) return false;

    final window = state.activeLlmMessages;
    if (window.length < 2) {
      if (!isAuto) {
        state = state.copyWith(errorMessage: '至少先聊完 1 轮再做知识沉淀哦');
      }
      return false;
    }

    final client = ref.read(aiClientProvider);
    if (client == null) {
      if (!isAuto) {
        state = state.copyWith(errorMessage: '请先配置 DeepSeek API Key 以执行知识沉淀');
      }
      return false;
    }

    // 活跃上下文窗口保留最近几条原话，更早部分归纳进前文摘要（但界面气泡依然完整保留）
    final keepCount = isAuto
        ? ContextCompactor.keepRecentMessages
        : (window.length > 6 ? 6 : 0);
    final splitIndex =
        (window.length - keepCount).clamp(1, window.length);
    final toCompact = window.sublist(0, splitIndex);
    final anchorId =
        splitIndex < window.length ? window[splitIndex].id : null;

    state = state.copyWith(
      isCompacting: true,
      clearError: true,
      statusBanner: isAuto
          ? '正在后台归纳前文摘要以保持最佳对话上下文…'
          : '正在提炼知识点并归纳工作记忆摘要…',
    );

    try {
      final compactor = ref.read(contextCompactorProvider);
      final result = await compactor.compact(
        aiClient: client,
        previousSummary: state.rollingSummary,
        existingKnowledgeIndex: state.knowledgeIndex,
        messagesToCompact: toCompact,
      );

      if (!ref.mounted) return false;

      final kbRepo = ref.read(knowledgeRepositoryProvider);
      if (result.entries.isNotEmpty) {
        await kbRepo.appendEntries(result.entries);
      }
      final updatedIndex = await kbRepo.readIndexMarkdown();
      final updatedDocs = await kbRepo.listDocs();

      final convRepo = ref.read(conversationRepositoryProvider);
      final noticeText = result.entries.isNotEmpty
          ? '已将 ${result.compactedMessageCount} 条前文归纳为工作记忆摘要，并沉淀 ${result.entries.length} 个知识点（上方历史可继续翻阅）'
          : '已将 ${result.compactedMessageCount} 条前文归纳为工作记忆摘要（上方历史可继续翻阅）';

      final noticeMsg = StudyMessage(
        id: convRepo.nextMessageId(),
        role: StudyMessageRole.system,
        content: noticeText,
        createdAt: DateTime.now(),
        isCompactionNotice: true,
      );

      // 保留所有聊天记录，仅移除旧的“工作记忆摘要”分隔条并把新分隔条插在活跃窗口起点处
      final cleaned = state.messages
          .where((m) => !(m.isCompactionNotice && m.content.contains('工作记忆摘要')))
          .toList();

      final insertAt = anchorId != null
          ? cleaned.indexWhere((m) => m.id == anchorId)
          : -1;
      if (insertAt >= 0) {
        cleaned.insert(insertAt, noticeMsg);
      } else {
        cleaned.add(noticeMsg);
      }

      // 计算本次已覆盖到 conversationalMessages 的哪一条，更新沉淀水位线
      final lastCompactedId = toCompact.last.id;
      final convList = cleaned.where((m) => !m.isCompactionNotice).toList();
      final compactedEndIdx =
          convList.indexWhere((m) => m.id == lastCompactedId);
      final minDistilled = compactedEndIdx >= 0
          ? compactedEndIdx + 1
          : state.lastDistilledCount;
      final nextDistilled = state.lastDistilledCount > minDistilled
          ? state.lastDistilledCount
          : minDistilled;

      final capped = _trimToDisplayCap(
        cleaned,
        lastDistilledCount: nextDistilled,
        contextWindowStartId: noticeMsg.id,
      );

      state = state.copyWith(
        messages: capped.messages,
        rollingSummary: result.rollingSummary,
        knowledgeIndex: updatedIndex,
        knowledgeDocs: updatedDocs,
        contextWindowStartId: capped.contextWindowStartId,
        clearContextWindowStart: capped.clearContextWindowStart,
        compactionCount: state.compactionCount + 1,
        lastDistilledCount: capped.lastDistilledCount,
        isCompacting: false,
        clearStatusBanner: true,
      );

      await _persistMemory();
      return true;
    } catch (e) {
      debugPrint('Compaction failed: $e');
      if (!ref.mounted) return false;
      state = state.copyWith(
        isCompacting: false,
        clearStatusBanner: true,
        errorMessage: isAuto ? null : '归纳摘要失败，原对话已完整保留：$e',
      );
      return false;
    }
  }

  /// 后台静默自动沉淀：只提炼新聊透的知识点写入 `KNOWLEDGE.md` 与 `docs/`，不折叠当前对话、不打断语音
  Future<void> _distillQuietlyInBackground() async {
    if (state.isCompacting || state.isGenerating) return;
    final client = ref.read(aiClientProvider);
    if (client == null) return;

    final active = state.conversationalMessages;
    final startIdx = state.lastDistilledCount.clamp(0, active.length);
    if (active.length - startIdx <
        ContextCompactor.autoDistillNewMessagesThreshold) {
      return;
    }

    final slice = active.sublist(startIdx);
    final newWatermark = active.length;

    state = state.copyWith(isCompacting: true);
    try {
      final compactor = ref.read(contextCompactorProvider);
      final result = await compactor.compact(
        aiClient: client,
        previousSummary: state.rollingSummary,
        existingKnowledgeIndex: state.knowledgeIndex,
        messagesToCompact: slice,
      );
      if (!ref.mounted) return;

      final kbRepo = ref.read(knowledgeRepositoryProvider);
      if (result.entries.isNotEmpty) {
        await kbRepo.appendEntries(result.entries);
      }
      final updatedIndex = await kbRepo.readIndexMarkdown();
      final updatedDocs = await kbRepo.listDocs();

      state = state.copyWith(
        knowledgeIndex: updatedIndex,
        knowledgeDocs: updatedDocs,
        lastDistilledCount: newWatermark,
        isCompacting: false,
      );
      await _persistMemory();
    } catch (e) {
      debugPrint('Quiet background distill skipped: $e');
      if (!ref.mounted) return;
      state = state.copyWith(isCompacting: false);
    }
  }

  // ------------------------------------------------------------------
  // 附件采集（拍照 / 相册选择 / 添加文件）
  // ------------------------------------------------------------------

  static const int maxPendingAttachments = 6;

  Future<void> pickCameraPhoto() async {
    if (state.isGenerating || state.isParsingAttachment) return;
    try {
      final item = await ref.read(attachmentPickerServiceProvider).pickFromCamera();
      if (!ref.mounted || item == null) return;
      _appendPendingAttachments([item]);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        errorMessage: e is StateError ? e.message : '无法打开相机：$e',
      );
    }
  }

  Future<void> pickGalleryImages() async {
    if (state.isGenerating || state.isParsingAttachment) return;
    try {
      final items =
          await ref.read(attachmentPickerServiceProvider).pickFromGallery();
      if (!ref.mounted || items.isEmpty) return;
      _appendPendingAttachments(items);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        errorMessage: e is StateError ? e.message : '无法选择相册图片：$e',
      );
    }
  }

  Future<void> pickFiles() async {
    if (state.isGenerating || state.isParsingAttachment) return;
    try {
      final items = await ref.read(attachmentPickerServiceProvider).pickFiles();
      if (!ref.mounted || items.isEmpty) return;
      _appendPendingAttachments(items);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        errorMessage: e is StateError ? e.message : '无法添加文件：$e',
      );
    }
  }

  /// 桌面端（macOS / Windows）直接 Cmd+V / Ctrl+V 粘贴剪贴板图片或文件，返回是否命中图片/文件
  Future<bool> pasteFromClipboard() async {
    if (state.isGenerating || state.isParsingAttachment) return false;
    try {
      final items = await ref
          .read(attachmentPickerServiceProvider)
          .pickFromClipboard();
      if (!ref.mounted || items.isEmpty) return false;
      _appendPendingAttachments(items);
      return true;
    } catch (e) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        errorMessage: e is StateError ? e.message : '粘贴剪贴板图片失败：$e',
      );
      return false;
    }
  }

  void _appendPendingAttachments(List<StudyAttachment> additions) {
    final merged = [...state.pendingAttachments, ...additions];
    if (merged.length > maxPendingAttachments) {
      state = state.copyWith(
        pendingAttachments: merged.sublist(0, maxPendingAttachments),
        errorMessage: '单条消息最多附加 $maxPendingAttachments 个图片或文件',
      );
      return;
    }
    state = state.copyWith(pendingAttachments: merged, clearError: true);
  }

  void removePendingAttachment(String id) {
    state = state.copyWith(
      pendingAttachments:
          state.pendingAttachments.where((a) => a.id != id).toList(),
    );
  }

  // ------------------------------------------------------------------
  // 对话发送 + 多模态附件 + 流式 TTS 实时联动 + 达上限自动沉淀压缩
  // ------------------------------------------------------------------

  Future<void> sendText(String rawText) async {
    final trimmed = rawText.trim();
    final pending = state.pendingAttachments;
    if ((trimmed.isEmpty && pending.isEmpty) ||
        state.isGenerating ||
        state.isParsingAttachment) {
      return;
    }

    // 每次新发问立刻打断上一轮语音播报
    await stopPlayback();

    final hasImages = pending.any((a) => a.isImage);
    final hasFiles = pending.any((a) => a.isFile);
    final text = trimmed.isNotEmpty
        ? trimmed
        : (hasFiles
            ? '请帮我梳理这份文件，用苏格拉底方式带我搞懂核心内容。'
            : (hasImages ? '请看看这些图片，用大白话带我理解里面的重点。' : ''));

    final convRepo = ref.read(conversationRepositoryProvider);

    if (SensitiveContentGuard.isSensitive(text)) {
      final userMsg = StudyMessage(
        id: convRepo.nextMessageId(),
        role: StudyMessageRole.user,
        content: text,
        createdAt: DateTime.now(),
        attachments: pending,
      );
      final warnMsg = StudyMessage(
        id: convRepo.nextMessageId(),
        role: StudyMessageRole.assistant,
        content: SensitiveContentGuard.friendlyWarningMessage(),
        createdAt: DateTime.now(),
      );
      state = state.copyWith(pendingAttachments: const []);
      await _appendMessages([userMsg, warnMsg]);
      return;
    }

    final client = ref.read(aiClientProvider);
    if (client == null) {
      final userMsg = StudyMessage(
        id: convRepo.nextMessageId(),
        role: StudyMessageRole.user,
        content: text,
        createdAt: DateTime.now(),
        attachments: pending,
      );
      final hintMsg = StudyMessage(
        id: convRepo.nextMessageId(),
        role: StudyMessageRole.assistant,
        content: '尚未配置 DeepSeek API Key，请先点击下方按钮前往设置页填写密钥。',
        createdAt: DateTime.now(),
      );
      state = state.copyWith(pendingAttachments: const []);
      await _appendMessages([userMsg, hintMsg]);
      return;
    }

    // 解析 PDF/Word/PPT 等需要 DeepSeek OCR 提取文字的文档
    List<StudyAttachment> resolvedAttachments = pending;
    if (pending.any(NativeAttachmentPickerService.needsOcr)) {
      final ocrClient = ref.read(deepSeekOcrClientProvider);
      if (ocrClient == null) {
        state = state.copyWith(
          errorMessage: '请先在设置中配置 DeepSeek API Key 以解析文档',
        );
        return;
      }

      state = state.copyWith(
        isParsingAttachment: true,
        clearError: true,
        statusBanner: '正在解析文档内容…',
      );
      try {
        final nextList = <StudyAttachment>[];
        for (final item in pending) {
          if (!NativeAttachmentPickerService.needsOcr(item)) {
            nextList.add(item);
            continue;
          }
          if (!ref.mounted) return;
          state = state.copyWith(statusBanner: '正在解析文档：${item.name}…');
          final bytes = await File(item.localPath).readAsBytes();
          final parsed = await ocrClient.parseDocument(
            bytes,
            filename: item.name,
          );
          nextList.add(item.copyWith(extractedText: parsed.text));
        }
        resolvedAttachments = nextList;
      } on OcrException catch (e) {
        if (!ref.mounted) return;
        state = state.copyWith(
          isParsingAttachment: false,
          clearStatusBanner: true,
          errorMessage: e.message,
        );
        return;
      } catch (e) {
        if (!ref.mounted) return;
        state = state.copyWith(
          isParsingAttachment: false,
          clearStatusBanner: true,
          errorMessage: '解析文档失败：$e',
        );
        return;
      }
      if (!ref.mounted) return;
      state = state.copyWith(
        isParsingAttachment: false,
        clearStatusBanner: true,
      );
    }

    final userMsg = StudyMessage(
      id: convRepo.nextMessageId(),
      role: StudyMessageRole.user,
      content: text,
      createdAt: DateTime.now(),
      attachments: resolvedAttachments,
    );

    state = state.copyWith(pendingAttachments: const []);
    await _appendMessages([userMsg]);

    if (KnowledgeOrganizer.looksLikeKnowledgeWriteRequest(text)) {
      await organizeKnowledgeBase(text);
      return;
    }

    if (MasteryCalibrator.looksLikeStartMasteryRequest(text)) {
      await _ensureMasteryProfileSilently(text, client);
    }

    state = state.copyWith(
      isGenerating: true,
      streamingText: '',
      clearError: true,
    );

    final settings = ref.read(aiSettingsProvider);
    final ttsClient = ref.read(deepSeekTtsClientProvider);
    final shouldAutoSpeak = settings.autoPlayTts && ttsClient != null;

    final chunker = TtsTextChunker();
    final earlyQueue = <String>[];
    var wsReady = false;
    var wsFailed = false;
    var llmCompleted = false;
    String completedReply = '';
    String? completedMessageId;
    final token = ++_playbackToken;

    if (shouldAutoSpeak) {
      state = state.copyWith(
        ttsPhase: TtsPlaybackPhase.connecting,
        playingMessageId: streamingMessageId,
      );
      unawaited(
        _openStreamingTts(
          ttsClient: ttsClient,
          voiceId: settings.ttsVoiceId,
          token: token,
          earlyQueue: earlyQueue,
          isLlmDone: () => llmCompleted,
          getCompletedReply: () => completedReply,
          getCompletedMessageId: () => completedMessageId,
          onReady: () => wsReady = true,
          onFailed: () => wsFailed = true,
        ),
      );
    }

    final sysPrompt = StudyModePrompt.buildSystemPrompt(
      knowledgeIndex: state.knowledgeIndex,
      rollingSummary: state.rollingSummary,
      focusedDocTitle: state.focusedDocTitle,
      focusedDocContent: state.focusedDocContent,
      activeMasteryProfile: state.activeMastery,
      webSearchEnabled: settings.enableWebSearch && settings.isDeepSeekEndpoint,
    );

    final wireMessages = await _buildWireMessages(
      sysPrompt,
      state.activeLlmMessages,
    );

    try {
      _llmSub = client
          .streamChat(
            wireMessages,
            enableWebSearch: settings.enableWebSearch,
          )
          .listen(
        (chunk) {
          if (!ref.mounted || chunk.isDone) return;
          if (chunk.statusHint != null &&
              chunk.statusHint!.isNotEmpty &&
              state.streamingText.isEmpty) {
            state = state.copyWith(statusBanner: chunk.statusHint);
          }
          if (chunk.delta.isEmpty) return;
          final nextStreaming = state.streamingText + chunk.delta;
          state = state.copyWith(
            streamingText: nextStreaming,
            clearStatusBanner: state.statusBanner != null,
          );

          if (shouldAutoSpeak && !wsFailed && token == _playbackToken) {
            final readyChunks = chunker.addDelta(chunk.delta);
            for (final piece in readyChunks) {
              if (wsReady && _activeTtsSession != null) {
                _activeTtsSession!.sendText(piece);
              } else {
                earlyQueue.add(piece);
              }
            }
          }
        },
        onError: (Object e) async {
          if (!ref.mounted) return;
          llmCompleted = true;
          final msg = _formatAiError(e);
          if (token == _playbackToken) {
            await stopPlayback();
          }
          final errBubble = StudyMessage(
            id: convRepo.nextMessageId(),
            role: StudyMessageRole.assistant,
            content: msg,
            createdAt: DateTime.now(),
          );
          state = state.copyWith(
            isGenerating: false,
            streamingText: '',
            clearStatusBanner: true,
            errorMessage: msg,
          );
          await _appendMessages([errBubble]);
        },
        onDone: () async {
          if (!ref.mounted) return;
          llmCompleted = true;
          final rawReply = state.streamingText.trim();
          final kbActionMatch = RegExp(
            r'\[KB_ACTION:\s*([^\]]+)\]',
            caseSensitive: false,
          ).firstMatch(rawReply);
          final kbAction = kbActionMatch?.group(1)?.trim();
          final fullReply = rawReply
              .replaceAll(
                RegExp(r'\s*\[KB_ACTION:\s*[^\]]+\]', caseSensitive: false),
                '',
              )
              .trim();
          completedReply = fullReply;
          String? savedId;

          state = state.copyWith(
            isGenerating: false,
            streamingText: '',
            clearStatusBanner: true,
          );

          if (fullReply.isNotEmpty) {
            final assistantMsg = StudyMessage(
              id: convRepo.nextMessageId(),
              role: StudyMessageRole.assistant,
              content: fullReply,
              createdAt: DateTime.now(),
            );
            savedId = assistantMsg.id;
            completedMessageId = savedId;
            await _appendMessages([assistantMsg]);
          }

          if (shouldAutoSpeak && fullReply.isNotEmpty && token == _playbackToken) {
            if (savedId != null && state.playingMessageId == streamingMessageId) {
              state = state.copyWith(playingMessageId: savedId);
            }

            if (wsFailed) {
              unawaited(
                _playViaHttp(
                  text: fullReply,
                  messageId: savedId ?? streamingMessageId,
                  voiceId: settings.ttsVoiceId,
                ),
              );
            } else {
              final tailChunks = chunker
                  .flush()
                  .map((p) => p
                      .replaceAll(
                        RegExp(r'\s*\[KB_ACTION:\s*[^\]]+\]',
                            caseSensitive: false),
                        '',
                      )
                      .trim())
                  .where((p) => p.isNotEmpty)
                  .toList();
              if (wsReady && _activeTtsSession != null) {
                for (final piece in tailChunks) {
                  _activeTtsSession!.sendText(piece);
                }
                _activeTtsSession!.finishText();
              } else {
                earlyQueue.addAll(tailChunks);
              }
            }
          } else if (token == _playbackToken && state.isSpeaking) {
            await stopPlayback();
          }

          if (kbAction != null && kbAction.isNotEmpty) {
            unawaited(
              organizeKnowledgeBase(
                kbAction,
                appendAssistantReply: false,
              ),
            );
            return;
          }

          // 回复结束后：活跃窗口触及上限时后台归纳摘要（不清屏）；每满 3 轮未沉淀新对话时静默沉淀
          final compactor = ref.read(contextCompactorProvider);
          if (compactor.shouldAutoCompact(state.activeLlmMessages)) {
            unawaited(compactAndDistillNow(isAuto: true));
          } else if (compactor.shouldAutoDistill(
            state.messages,
            lastDistilledCount: state.lastDistilledCount,
          )) {
            unawaited(_distillQuietlyInBackground());
          }

          // 若处于某学科自适应学习中，每满 2 轮后台静默校准水平与路线（用户无感）
          final calibrator = ref.read(masteryCalibratorProvider);
          if (calibrator.shouldAutoCalibrate(
            state.messages,
            activeProfile: state.activeMastery,
          )) {
            unawaited(_calibrateMasteryQuietlyInBackground());
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      llmCompleted = true;
      final msg = _formatAiError(e);
      await stopPlayback();
      state = state.copyWith(
        isGenerating: false,
        streamingText: '',
        errorMessage: msg,
      );
      final errBubble = StudyMessage(
        id: convRepo.nextMessageId(),
        role: StudyMessageRole.assistant,
        content: msg,
        createdAt: DateTime.now(),
      );
      await _appendMessages([errBubble]);
    }
  }

  Future<List<AiMessage>> _buildWireMessages(
    String sysPrompt,
    List<StudyMessage> messages,
  ) async {
    // 仅对最近携带图片的消息加载 base64（最多保留最近 4 张图），避免长对话上下文爆体积
    final imageMessageIndices = <int>{};
    var remainingImageSlots = 4;
    for (var i = messages.length - 1; i >= 0 && remainingImageSlots > 0; i--) {
      final imgs = messages[i].attachments.where((a) => a.isImage).length;
      if (imgs > 0) {
        imageMessageIndices.add(i);
        remainingImageSlots -= imgs;
      }
    }

    final wire = <AiMessage>[AiMessage.system(sysPrompt)];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final role = switch (m.role) {
        StudyMessageRole.user => AiRole.user,
        StudyMessageRole.assistant => AiRole.assistant,
        StudyMessageRole.system => AiRole.system,
      };

      final textBuf = StringBuffer(m.content);
      final imageParts = <AiImagePart>[];

      for (final att in m.attachments) {
        if (att.isFile) {
          final body = att.extractedText?.trim() ?? '';
          if (body.isNotEmpty) {
            textBuf
              ..writeln()
              ..writeln()
              ..writeln('【附件文件：${att.name}】')
              ..writeln(body);
          } else {
            textBuf
              ..writeln()
              ..writeln('【附件文件：${att.name}（未提取到文字）】');
          }
        } else if (att.isImage && imageMessageIndices.contains(i)) {
          try {
            final file = File(att.localPath);
            if (file.existsSync()) {
              final bytes = await file.readAsBytes();
              imageParts.add(
                AiImagePart(
                  mimeType: att.mimeType,
                  base64Data: base64Encode(bytes),
                ),
              );
            }
          } catch (e) {
            debugPrint('Load image attachment failed (${att.name}): $e');
          }
        }
      }

      wire.add(AiMessage(role, textBuf.toString().trim(), images: imageParts));
    }
    return wire;
  }

  Future<void> _openStreamingTts({
    required DeepSeekTtsClient ttsClient,
    required String voiceId,
    required int token,
    required List<String> earlyQueue,
    required bool Function() isLlmDone,
    required String Function() getCompletedReply,
    required String? Function() getCompletedMessageId,
    required VoidCallback onReady,
    required VoidCallback onFailed,
  }) async {
    try {
      final session = await ttsClient.openStreamSession(voiceId: voiceId);
      if (!ref.mounted || token != _playbackToken) {
        await session.cancel();
        return;
      }

      _activeTtsSession = session;
      final player = ref.read(streamingAudioPlayerProvider);
      player.beginSession(
        onComplete: () {
          if (!ref.mounted || token != _playbackToken) return;
          state = state.copyWith(
            ttsPhase: TtsPlaybackPhase.idle,
            clearPlayingMessageId: true,
          );
        },
      );

      state = state.copyWith(ttsPhase: TtsPlaybackPhase.playing);

      _ttsAudioSub = session.audioChunks.listen(
        (pcmChunk) {
          if (token != _playbackToken) return;
          player.feedPcm16(pcmChunk);
        },
        onError: (Object e) {
          debugPrint('TTS WS stream error: $e');
          if (!ref.mounted || token != _playbackToken) return;
          player.stop();
          state = state.copyWith(
            ttsPhase: TtsPlaybackPhase.idle,
            clearPlayingMessageId: true,
          );
        },
        onDone: () {
          if (!ref.mounted || token != _playbackToken) return;
          player.markEndOfStream();
        },
      );

      onReady();

      for (final piece in earlyQueue) {
        session.sendText(piece);
      }
      earlyQueue.clear();

      if (isLlmDone()) {
        session.finishText();
      }
    } catch (e) {
      debugPrint('TTS WS connect failed, will fallback to HTTP: $e');
      onFailed();
      if (!ref.mounted || token != _playbackToken) return;
      if (isLlmDone()) {
        final reply = getCompletedReply();
        if (reply.isNotEmpty) {
          unawaited(
            _playViaHttp(
              text: reply,
              messageId: getCompletedMessageId() ?? streamingMessageId,
              voiceId: voiceId,
            ),
          );
        } else {
          state = state.copyWith(
            ttsPhase: TtsPlaybackPhase.idle,
            clearPlayingMessageId: true,
          );
        }
      } else {
        state = state.copyWith(
          ttsPhase: TtsPlaybackPhase.idle,
          clearPlayingMessageId: true,
        );
      }
    }
  }

  Future<void> cancelGeneration() async {
    final partial = state.streamingText.trim();
    _cancelLlmInternal();
    await stopPlayback();

    state = state.copyWith(
      isGenerating: false,
      streamingText: '',
      clearStatusBanner: true,
    );

    if (partial.isNotEmpty) {
      final convRepo = ref.read(conversationRepositoryProvider);
      await _appendMessages([
        StudyMessage(
          id: convRepo.nextMessageId(),
          role: StudyMessageRole.assistant,
          content: partial,
          createdAt: DateTime.now(),
        ),
      ]);
    }
  }

  // ------------------------------------------------------------------
  // 语音录制 & DeepSeek ASR 转文字
  // ------------------------------------------------------------------

  Future<void> startRecording() async {
    if (state.isGenerating || state.isRecording || state.isTranscribing) return;
    final recToken = ++_recordingToken;

    await stopPlayback();
    if (!ref.mounted || recToken != _recordingToken) return;

    final recorder = ref.read(voiceRecorderServiceProvider);
    try {
      await _ampSub?.cancel();
      await _durSub?.cancel();

      _ampSub = recorder.amplitudeStream.listen((amp) {
        if (!ref.mounted || recToken != _recordingToken || !state.isRecording) {
          return;
        }
        state = state.copyWith(recordingAmplitude: amp);
      });
      _durSub = recorder.durationStream.listen((dur) {
        if (!ref.mounted || recToken != _recordingToken || !state.isRecording) {
          return;
        }
        state = state.copyWith(recordingDuration: dur);
      });

      state = state.copyWith(
        voicePhase: VoiceInputPhase.recording,
        recordingAmplitude: 0.0,
        recordingDuration: Duration.zero,
        clearError: true,
      );

      await recorder.start(
        onMaxDurationReached: () {
          unawaited(stopRecordingAndTranscribe());
        },
      );

      if (!ref.mounted || recToken != _recordingToken) {
        await recorder.cancel();
        return;
      }
    } catch (e) {
      await _ampSub?.cancel();
      await _durSub?.cancel();
      if (!ref.mounted || recToken != _recordingToken) return;
      state = state.copyWith(
        voicePhase: VoiceInputPhase.idle,
        recordingAmplitude: 0.0,
        recordingDuration: Duration.zero,
        errorMessage: e is StateError ? e.message : '无法启动录音：$e',
      );
    }
  }

  Future<void> cancelRecording() async {
    _recordingToken++;
    if (!state.isRecording) return;
    await _ampSub?.cancel();
    await _durSub?.cancel();
    await ref.read(voiceRecorderServiceProvider).cancel();
    if (!ref.mounted) return;
    state = state.copyWith(
      voicePhase: VoiceInputPhase.idle,
      recordingAmplitude: 0.0,
      recordingDuration: Duration.zero,
    );
  }

  Future<void> stopRecordingAndTranscribe({
    void Function(String text)? onTranscribedForInput,
  }) async {
    _recordingToken++;
    if (!state.isRecording) return;

    await _ampSub?.cancel();
    await _durSub?.cancel();
    final recorder = ref.read(voiceRecorderServiceProvider);
    final recorded = await recorder.stop();

    if (!ref.mounted) return;
    if (recorded == null || recorded.wavBytes.length <= 44) {
      state = state.copyWith(
        voicePhase: VoiceInputPhase.idle,
        recordingAmplitude: 0.0,
        recordingDuration: Duration.zero,
        errorMessage: '说话时间太短，没有录到有效语音',
      );
      return;
    }

    final asrClient = ref.read(deepSeekAsrClientProvider);
    if (asrClient == null) {
      state = state.copyWith(
        voicePhase: VoiceInputPhase.idle,
        recordingAmplitude: 0.0,
        recordingDuration: Duration.zero,
        errorMessage: '请先在设置中配置 DeepSeek API Key 以使用语音识别',
      );
      return;
    }

    state = state.copyWith(
      voicePhase: VoiceInputPhase.transcribing,
      recordingAmplitude: 0.0,
      clearError: true,
    );

    try {
      final result = await asrClient.transcribeWav(recorded.wavBytes);
      if (!ref.mounted) return;

      state = state.copyWith(
        voicePhase: VoiceInputPhase.idle,
        recordingDuration: Duration.zero,
      );

      final text = result.text.trim();
      if (text.isEmpty) {
        state = state.copyWith(errorMessage: '没有识别到清晰内容，请再说一次');
        return;
      }

      final settings = ref.read(aiSettingsProvider);
      if (settings.autoSendAfterAsr) {
        await sendText(text);
      } else {
        onTranscribedForInput?.call(text);
      }
    } on AsrException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        voicePhase: VoiceInputPhase.idle,
        recordingDuration: Duration.zero,
        errorMessage: e.message,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        voicePhase: VoiceInputPhase.idle,
        recordingDuration: Duration.zero,
        errorMessage: '语音识别异常：$e',
      );
    }
  }

  // ------------------------------------------------------------------
  // 历史气泡重播、音色试听与随时打断
  // ------------------------------------------------------------------

  Future<void> toggleMessagePlayback(StudyMessage msg) async {
    if (state.isSpeaking && state.playingMessageId == msg.id) {
      await stopPlayback();
      return;
    }
    final settings = ref.read(aiSettingsProvider);
    await _playViaHttp(
      text: msg.content,
      messageId: msg.id,
      voiceId: settings.ttsVoiceId,
    );
  }

  Future<void> previewVoice(String voiceId, {String? apiKeyOverride}) async {
    final sampleText = voiceId == 'tide'
        ? '你好，我是暗潮。我会用清晰的逻辑和生活类比，陪你一步步把难题彻底想明白。'
        : '你好，我是海星。有什么想弄懂的问题，尽管开口问我，咱们一步步来聊。';
    await _playViaHttp(
      text: sampleText,
      messageId: '__preview_$voiceId',
      voiceId: voiceId,
      apiKeyOverride: apiKeyOverride,
    );
  }

  Future<void> _playViaHttp({
    required String text,
    required String messageId,
    required String voiceId,
    String? apiKeyOverride,
  }) async {
    await stopPlayback();
    DeepSeekTtsClient? tempClient;
    DeepSeekTtsClient? ttsClient = ref.read(deepSeekTtsClientProvider);
    final overrideKey = apiKeyOverride?.trim() ?? '';
    if (overrideKey.isNotEmpty) {
      tempClient = DeepSeekTtsClient(
        settings: ref.read(aiSettingsProvider),
        apiKey: overrideKey,
      );
      ttsClient = tempClient;
    }
    if (ttsClient == null) {
      state = state.copyWith(errorMessage: '请先输入或保存 DeepSeek API Key 以使用语音朗读');
      return;
    }

    final token = ++_playbackToken;
    state = state.copyWith(
      ttsPhase: TtsPlaybackPhase.connecting,
      playingMessageId: messageId,
      clearError: true,
    );

    final player = ref.read(streamingAudioPlayerProvider);
    var started = false;

    try {
      await for (final chunk in ttsClient.synthesizeStream(
        text,
        voiceId: voiceId,
      )) {
        if (!ref.mounted || token != _playbackToken) return;
        if (!started) {
          started = true;
          player.beginSession(
            onComplete: () {
              if (!ref.mounted || token != _playbackToken) return;
              state = state.copyWith(
                ttsPhase: TtsPlaybackPhase.idle,
                clearPlayingMessageId: true,
              );
            },
          );
          state = state.copyWith(ttsPhase: TtsPlaybackPhase.playing);
        }
        player.feedPcm16(chunk);
      }

      if (!ref.mounted || token != _playbackToken) return;
      if (started) {
        player.markEndOfStream();
      } else {
        state = state.copyWith(
          ttsPhase: TtsPlaybackPhase.idle,
          clearPlayingMessageId: true,
        );
      }
    } on TtsException catch (e) {
      if (!ref.mounted || token != _playbackToken) return;
      player.stop();
      state = state.copyWith(
        ttsPhase: TtsPlaybackPhase.idle,
        clearPlayingMessageId: true,
        errorMessage: e.message,
      );
    } catch (e) {
      if (!ref.mounted || token != _playbackToken) return;
      player.stop();
      state = state.copyWith(
        ttsPhase: TtsPlaybackPhase.idle,
        clearPlayingMessageId: true,
        errorMessage: '语音播报失败：$e',
      );
    } finally {
      tempClient?.dispose();
    }
  }

  Future<void> stopPlayback() async {
    _playbackToken++;
    await _ttsAudioSub?.cancel();
    _ttsAudioSub = null;
    final ws = _activeTtsSession;
    _activeTtsSession = null;
    if (ws != null) {
      await ws.cancel();
    }
    ref.read(streamingAudioPlayerProvider).stop();

    if (ref.mounted && state.isSpeaking) {
      state = state.copyWith(
        ttsPhase: TtsPlaybackPhase.idle,
        clearPlayingMessageId: true,
      );
    }
  }

  Future<void> toggleAutoPlayTts() async {
    final current = ref.read(aiSettingsProvider);
    final next = current.copyWith(autoPlayTts: !current.autoPlayTts);
    if (!next.autoPlayTts) {
      await stopPlayback();
    }
    try {
      await ref.read(configRepositoryProvider).saveAiSettings(next);
      ref.invalidate(appConfigProvider);
    } catch (e) {
      debugPrint('Save autoPlayTts failed: $e');
    }
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }

  // ------------------------------------------------------------------
  // 内部持久化与清理
  // ------------------------------------------------------------------

  Future<void> _appendMessages(List<StudyMessage> additions) async {
    final merged = [...state.messages, ...additions];
    final capped = _trimToDisplayCap(
      merged,
      lastDistilledCount: state.lastDistilledCount,
      contextWindowStartId: state.contextWindowStartId,
    );
    state = state.copyWith(
      messages: capped.messages,
      lastDistilledCount: capped.lastDistilledCount,
      contextWindowStartId: capped.contextWindowStartId,
      clearContextWindowStart: capped.clearContextWindowStart,
    );
    await _persistMemory();
  }

  /// 控制界面与本地 `conversation.json` 的最大有效对话条数（默认保留最近 120 条 = 60 轮），
  /// 仅在超出上限时淘汰最古早条目，同时精确修正沉淀水位线与滑动窗口游标。
  ({
    List<StudyMessage> messages,
    int lastDistilledCount,
    String? contextWindowStartId,
    bool clearContextWindowStart,
  }) _trimToDisplayCap(
    List<StudyMessage> rawMessages, {
    required int lastDistilledCount,
    required String? contextWindowStartId,
  }) {
    final totalConv =
        rawMessages.where((m) => !m.isCompactionNotice).length;
    final excess = totalConv - ContextCompactor.maxDisplayMessages;
    if (excess <= 0) {
      return (
        messages: rawMessages,
        lastDistilledCount: lastDistilledCount,
        contextWindowStartId: contextWindowStartId,
        clearContextWindowStart: false,
      );
    }

    var droppedConv = 0;
    var cutIndex = 0;
    while (cutIndex < rawMessages.length && droppedConv < excess) {
      if (!rawMessages[cutIndex].isCompactionNotice) {
        droppedConv++;
      }
      cutIndex++;
    }
    while (cutIndex < rawMessages.length &&
        rawMessages[cutIndex].isCompactionNotice) {
      cutIndex++;
    }

    final trimmed = rawMessages.sublist(cutIndex);
    final remainingConv =
        trimmed.where((m) => !m.isCompactionNotice).length;
    final nextDistilled =
        (lastDistilledCount - droppedConv).clamp(0, remainingConv);

    final keepWindowStart = contextWindowStartId != null &&
        trimmed.any((m) => m.id == contextWindowStartId);

    return (
      messages: trimmed,
      lastDistilledCount: nextDistilled,
      contextWindowStartId: keepWindowStart ? contextWindowStartId : null,
      clearContextWindowStart: !keepWindowStart,
    );
  }

  Future<void> _persistMemory() async {
    final memory = ConversationMemory(
      rollingSummary: state.rollingSummary,
      messages: state.messages,
      focusedDocSlug: state.focusedDocSlug,
      activeMasterySlug: state.activeMasterySlug,
      contextWindowStartId: state.contextWindowStartId,
      compactionCount: state.compactionCount,
      lastDistilledCount: state.lastDistilledCount,
      updatedAt: DateTime.now(),
    );
    await ref.read(conversationRepositoryProvider).save(memory);
  }

  void _cancelLlmInternal() {
    _llmSub?.cancel();
    _llmSub = null;
    ref.read(aiClientProvider)?.cancel();
  }

  void _cleanupAll() {
    _llmSub?.cancel();
    _ampSub?.cancel();
    _durSub?.cancel();
    _ttsAudioSub?.cancel();
    unawaited(_activeTtsSession?.cancel());
  }

  String _formatAiError(Object e) {
    if (e is AiException) {
      switch (e.kind) {
        case AiErrorKind.notConfigured:
          return '尚未配置 DeepSeek API Key，请前往设置页填写。';
        case AiErrorKind.unauthorized:
          return 'API Key 无效或鉴权失败，请检查密钥是否正确。';
        case AiErrorKind.contentFilter:
          return '内容触发安全合规审查，请换个表达重新提问。';
        case AiErrorKind.rateLimited:
          return '请求频次超限或账户余额不足，请稍后重试。';
        case AiErrorKind.modelNotFound:
          return '找不到指定模型，请在设置中确认使用 deepseek-flash 或 deepseek-v4-pro。';
        case AiErrorKind.network:
          return '网络连接异常，请检查网络后重试。';
        case AiErrorKind.server:
          return 'DeepSeek 服务端暂时繁忙，请稍后重试。';
        case AiErrorKind.badRequest:
          return e.detail.isNotEmpty ? e.detail : '请求参数异常。';
        case AiErrorKind.malformedResponse:
        case AiErrorKind.cancelled:
        case AiErrorKind.unknown:
          return '调用异常：${e.message}';
      }
    }
    return '发送失败：$e';
  }
}
