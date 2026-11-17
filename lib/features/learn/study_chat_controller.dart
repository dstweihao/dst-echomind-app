import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ai/ai_client.dart';
import '../../data/ai/context_compactor.dart';
import '../../data/ai/prompts/study_mode_prompt.dart';
import '../../data/ai/sensitive_content_guard.dart';
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
    this.errorMessage,
    this.statusBanner,
    this.hydrated = false,
  });

  bool get isSpeaking => ttsPhase != TtsPlaybackPhase.idle;
  bool get isRecording => voicePhase == VoiceInputPhase.recording;
  bool get isTranscribing => voicePhase == VoiceInputPhase.transcribing;
  bool get hasConversation => messages.isNotEmpty || streamingText.isNotEmpty;

  /// 参与上下文的有效对话消息
  List<StudyMessage> get conversationalMessages =>
      messages.where((m) => !m.isCompactionNotice).toList();

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

    final memory = await convRepo.load();
    final indexMd = await kbRepo.readIndexMarkdown();
    final docs = await kbRepo.listDocs();

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

    if (!ref.mounted) return;
    state = state.copyWith(
      messages: memory.messages,
      rollingSummary: memory.rollingSummary,
      knowledgeIndex: indexMd,
      knowledgeDocs: docs,
      focusedDocSlug: focusedTitle != null ? memory.focusedDocSlug : null,
      focusedDocTitle: focusedTitle,
      focusedDocContent: focusedBody,
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
      clearError: true,
    );
    await _persistMemory();

    await sendText(
      '我想复习「${doc.categoryName}」里沉淀的内容，请挑其中一个容易忘或有意思的点，用苏格拉底方式考考我。',
    );
  }

  /// 取消当前挂载的专题复习上下文
  Future<void> clearFocusedDoc() async {
    if (state.focusedDocSlug == null) return;
    state = state.copyWith(clearFocusedDoc: true);
    await _persistMemory();
  }

  /// 手动一键「沉淀并压缩」当前对话
  Future<bool> compactAndDistillNow({bool isAuto = false}) async {
    if (state.isCompacting || state.isGenerating) return false;

    final active = state.conversationalMessages;
    if (active.length < 2) {
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

    // 保留最近几条工作记忆，把更早的旧对话沉淀并压缩；若手动触发且条数较少，则至少保留最后 2 条
    final keepCount = isAuto
        ? ContextCompactor.keepRecentMessages
        : (active.length > 4 ? 2 : 0);
    final splitIndex =
        (active.length - keepCount).clamp(1, active.length);
    final toCompact = active.sublist(0, splitIndex);
    final compactedIds = toCompact.map((m) => m.id).toSet();

    state = state.copyWith(
      isCompacting: true,
      clearError: true,
      statusBanner: isAuto
          ? '对话达到上下文上限，正在后台沉淀知识并压缩上下文…'
          : '正在提炼知识点到 KNOWLEDGE.md 与 docs/ …',
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
          ? '已压缩 ${result.compactedMessageCount} 条对话，并沉淀 ${result.entries.length} 个知识点至 KNOWLEDGE.md 及 ${result.entries.map((e) => 'docs/${e.categorySlug}.md').toSet().join('、')}'
          : '已将 ${result.compactedMessageCount} 条前文对话压缩为工作记忆摘要，继续畅聊吧';

      final noticeMsg = StudyMessage(
        id: convRepo.nextMessageId(),
        role: StudyMessageRole.system,
        content: noticeText,
        createdAt: DateTime.now(),
        isCompactionNotice: true,
      );

      // 仅移除本次已压缩的旧消息，完整保留压缩期间用户新发的任何对话
      final remaining = state.messages
          .where((m) => !m.isCompactionNotice && !compactedIds.contains(m.id))
          .toList();

      state = state.copyWith(
        messages: [noticeMsg, ...remaining],
        rollingSummary: result.rollingSummary,
        knowledgeIndex: updatedIndex,
        knowledgeDocs: updatedDocs,
        compactionCount: state.compactionCount + 1,
        lastDistilledCount: remaining.length,
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
        errorMessage: isAuto ? null : '沉淀压缩失败，原对话已完整保留：$e',
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
  // 对话发送 + 流式 TTS 实时联动 + 达上限自动沉淀压缩
  // ------------------------------------------------------------------

  Future<void> sendText(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || state.isGenerating) return;

    // 每次新发问立刻打断上一轮语音播报
    await stopPlayback();

    final convRepo = ref.read(conversationRepositoryProvider);
    final userMsg = StudyMessage(
      id: convRepo.nextMessageId(),
      role: StudyMessageRole.user,
      content: text,
      createdAt: DateTime.now(),
    );

    if (SensitiveContentGuard.isSensitive(text)) {
      final warnMsg = StudyMessage(
        id: convRepo.nextMessageId(),
        role: StudyMessageRole.assistant,
        content: SensitiveContentGuard.friendlyWarningMessage(),
        createdAt: DateTime.now(),
      );
      await _appendMessages([userMsg, warnMsg]);
      return;
    }

    await _appendMessages([userMsg]);

    final client = ref.read(aiClientProvider);
    if (client == null) {
      final hintMsg = StudyMessage(
        id: convRepo.nextMessageId(),
        role: StudyMessageRole.assistant,
        content: '尚未配置 DeepSeek API Key，请先点击下方按钮前往设置页填写密钥。',
        createdAt: DateTime.now(),
      );
      await _appendMessages([hintMsg]);
      return;
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
    );

    final wireMessages = <AiMessage>[
      AiMessage.system(sysPrompt),
      for (final m in state.conversationalMessages)
        AiMessage(
          switch (m.role) {
            StudyMessageRole.user => AiRole.user,
            StudyMessageRole.assistant => AiRole.assistant,
            StudyMessageRole.system => AiRole.system,
          },
          m.content,
        ),
    ];

    try {
      _llmSub = client.streamChat(wireMessages).listen(
        (chunk) {
          if (!ref.mounted || chunk.isDone) return;
          final nextStreaming = state.streamingText + chunk.delta;
          state = state.copyWith(streamingText: nextStreaming);

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
            errorMessage: msg,
          );
          await _appendMessages([errBubble]);
        },
        onDone: () async {
          if (!ref.mounted) return;
          llmCompleted = true;
          final fullReply = state.streamingText.trim();
          completedReply = fullReply;
          String? savedId;

          state = state.copyWith(
            isGenerating: false,
            streamingText: '',
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
              final tailChunks = chunker.flush();
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

          // 回复结束后自动沉淀为主：触及上限时自动沉淀+压缩；未达上限但满 3 轮时静默自动沉淀知识点
          final compactor = ref.read(contextCompactorProvider);
          if (compactor.shouldAutoCompact(state.messages)) {
            unawaited(compactAndDistillNow(isAuto: true));
          } else if (compactor.shouldAutoDistill(
            state.messages,
            lastDistilledCount: state.lastDistilledCount,
          )) {
            unawaited(_distillQuietlyInBackground());
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
    state = state.copyWith(
      messages: [...state.messages, ...additions],
    );
    await _persistMemory();
  }

  Future<void> _persistMemory() async {
    final memory = ConversationMemory(
      rollingSummary: state.rollingSummary,
      messages: state.messages,
      focusedDocSlug: state.focusedDocSlug,
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
