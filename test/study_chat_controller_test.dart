import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:echomind_app/data/ai/ai_client.dart';
import 'package:echomind_app/data/app_paths.dart';
import 'package:echomind_app/data/storage/memory_file_store.dart';
import 'package:echomind_app/data/voice/deepseek_asr_client.dart';
import 'package:echomind_app/data/voice/deepseek_tts_client.dart';
import 'package:echomind_app/data/voice/streaming_audio_player.dart';
import 'package:echomind_app/data/voice/voice_recorder_service.dart';
import 'package:echomind_app/data/voice/wav_encoder.dart';
import 'package:echomind_app/domain/ai_enums_bridge.dart';
import 'package:echomind_app/domain/models/ai_settings.dart';
import 'package:echomind_app/domain/models/knowledge_models.dart';
import 'package:echomind_app/features/learn/study_chat_controller.dart';
import 'package:echomind_app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeAiClient implements AiClient {
  final List<String> deltas;
  final String compactJsonReply;
  List<AiMessage>? lastStreamMessages;

  _FakeAiClient(this.deltas, {required this.compactJsonReply});

  @override
  Stream<AiChunk> streamChat(
    List<AiMessage> messages, {
    bool? enableWebSearch,
  }) async* {
    lastStreamMessages = messages;
    for (final d in deltas) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      yield AiChunk(d);
    }
    yield AiChunk.done;
  }

  @override
  Future<String> chat(
    List<AiMessage> messages, {
    bool? enableWebSearch,
  }) async =>
      compactJsonReply;

  @override
  Future<void> testConnection() async {}

  @override
  void cancel() {}

  @override
  void dispose() {}
}

class _FakeVoiceRecorder implements VoiceRecorderService {
  final _ampCtrl = StreamController<double>.broadcast();
  final _durCtrl = StreamController<Duration>.broadcast();
  bool _recording = false;

  @override
  Stream<double> get amplitudeStream => _ampCtrl.stream;

  @override
  Stream<Duration> get durationStream => _durCtrl.stream;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start({void Function()? onMaxDurationReached}) async {
    _recording = true;
    _ampCtrl.add(0.6);
    _durCtrl.add(const Duration(seconds: 2));
  }

  @override
  Future<RecordedAudio?> stop() async {
    _recording = false;
    return RecordedAudio(
      wavBytes: WavEncoder.encodePcm16ToWav(Uint8List(3200)),
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Future<void> cancel() async {
    _recording = false;
  }

  @override
  Future<void> dispose() async {
    await _ampCtrl.close();
    await _durCtrl.close();
  }
}

class _FakeSocketChannel implements TtsSocketChannel {
  final incoming = StreamController<dynamic>();
  final sentFrames = <String>[];
  bool closed = false;

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  void sendTextFrame(String text) {
    sentFrames.add(text);
    final map = jsonDecode(text) as Map<String, dynamic>;
    if (map['event'] == 'text') {
      incoming.add(Uint8List.fromList([0x00, 0x20, 0x00, 0x40]));
    } else if (map['event'] == 'finish_text') {
      incoming.add(jsonEncode({'event': 'finish', 'code': 'success'}));
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!incoming.isClosed) await incoming.close();
  }
}

class _FakeAudioPlayer implements StreamingAudioPlayer {
  bool _playing = false;
  int fedBytes = 0;
  int stopCount = 0;
  bool ended = false;

  @override
  bool get isPlaying => _playing;

  @override
  void beginSession({void Function()? onComplete}) {
    _playing = true;
    ended = false;
  }

  @override
  void feedPcm16(Uint8List pcmBytes) {
    fedBytes += pcmBytes.length;
  }

  @override
  void markEndOfStream() {
    ended = true;
  }

  @override
  void stop() {
    if (_playing) stopCount++;
    _playing = false;
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('单会话完整闭环：语音问答 + 流式自动播报打断 + 沉淀写入 KNOWLEDGE.md 与 docs/economics.md 并压缩上下文', () async {
    final store = MemoryFileStore();
    final compactJson = jsonEncode({
      'rolling_summary': '用户已用小岛苹果模型理解了通货膨胀。',
      'entries': [
        {
          'category_slug': 'economics',
          'category_name': '经济学与金融',
          'topic': '通货膨胀',
          'one_liner': '商品不变但钱变多，导致每块钱购买力缩水。',
          'analogy': '小岛 10 个苹果配 100 块变 200 块',
          'misconception': '',
          'feynman_note': '钱印多了，物价自然涨。',
        },
      ],
    });

    final fakeAi = _FakeAiClient(
      ['通货膨胀就像小岛上的钱变多了。', '你猜苹果会涨价吗？'],
      compactJsonReply: compactJson,
    );
    final fakeRecorder = _FakeVoiceRecorder();
    final fakeSocket = _FakeSocketChannel();
    final fakePlayer = _FakeAudioPlayer();

    final fakeAsr = DeepSeekAsrClient(
      endpoint: 'https://api.deepseek.com/v1/tools/asr',
      apiKey: 'sk-test',
      httpClient: MockClient.streaming((_, stream) async {
        await stream.toBytes();
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'text': '什么是通货膨胀？'}))),
          200,
        );
      }),
    );

    final fakeTts = DeepSeekTtsClient(
      settings: const AiSettings(enabled: true, autoPlayTts: true),
      apiKey: 'sk-test',
      socketConnector: (_, {required headers}) async => fakeSocket,
    );

    final container = ProviderContainer(
      overrides: [
        initialStorageRootProvider.overrideWithValue(''),
        fileStoreProvider.overrideWithValue(store),
        aiSettingsProvider.overrideWithValue(
          const AiSettings(
            enabled: true,
            autoPlayTts: true,
            autoSendAfterAsr: true,
          ),
        ),
        aiApiKeyProvider.overrideWith((ref) async => 'sk-test'),
        aiClientProvider.overrideWithValue(fakeAi),
        deepSeekAsrClientProvider.overrideWithValue(fakeAsr),
        deepSeekTtsClientProvider.overrideWithValue(fakeTts),
        voiceRecorderServiceProvider.overrideWithValue(fakeRecorder),
        streamingAudioPlayerProvider.overrideWithValue(fakePlayer),
      ],
    );
    addTearDown(container.dispose);

    final ctrl = container.read(studyChatControllerProvider.notifier);

    // 1. 录音 → ASR → 自动发问 → 流式 TTS 自动播报
    await ctrl.startRecording();
    expect(container.read(studyChatControllerProvider).isRecording, true);

    await ctrl.stopRecordingAndTranscribe();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final afterReply = container.read(studyChatControllerProvider);
    expect(afterReply.isGenerating, false);
    expect(afterReply.conversationalMessages.length, 2);
    expect(fakeAi.lastStreamMessages?.first.content, contains('苏格拉底'));
    expect(fakeSocket.sentFrames.length, greaterThanOrEqualTo(2));
    expect(fakePlayer.fedBytes, greaterThan(0));
    expect(fakePlayer.ended, true);
    expect(afterReply.isSpeaking, true);

    // 2. 一键打断静音
    await ctrl.stopPlayback();
    expect(container.read(studyChatControllerProvider).isSpeaking, false);
    expect(fakePlayer.stopCount, greaterThanOrEqualTo(1));

    // 3. 触发沉淀压缩 → 写入 KNOWLEDGE.md + docs/economics.md 并压缩工作记忆
    final compacted = await ctrl.compactAndDistillNow();
    expect(compacted, true);

    final afterCompact = container.read(studyChatControllerProvider);
    expect(afterCompact.rollingSummary, contains('小岛苹果模型'));
    expect(afterCompact.knowledgeDocs.length, 1);
    expect(afterCompact.knowledgeDocs.first.slug, 'economics');
    expect(afterCompact.knowledgeIndex, contains('通货膨胀'));
    expect(afterCompact.messages.any((m) => m.isCompactionNotice), true);
    // 非破坏性归纳：原有聊天历史仍保留在屏幕上供翻阅，但发给模型的活跃窗口已归零
    expect(afterCompact.conversationalMessages.length, 2);
    expect(afterCompact.activeLlmMessages, isEmpty);

    // 验证物理纯文本文件已落盘至 FileStore
    expect(await store.exists(AppPaths.knowledgeIndexFile), true);
    expect(await store.exists(AppPaths.knowledgeDocFile('economics')), true);
    expect(await store.exists(AppPaths.conversationFile), true);
  });

  test('三层滑动窗口：满 40 条归纳前文摘要且不删屏显历史，超出 120 条才淘汰最古早条目', () async {
    final store = MemoryFileStore();
    final initialMsgs = List.generate(
      40,
      (i) => StudyMessage(
        id: 'm-$i',
        role: i.isEven ? StudyMessageRole.user : StudyMessageRole.assistant,
        content: '第 $i 条对话',
        createdAt: DateTime(2026, 11, 20),
      ),
    );
    await store.write(
      AppPaths.conversationFile,
      jsonEncode(
        ConversationMemory(
          messages: initialMsgs,
          updatedAt: DateTime(2026, 11, 20),
        ).toJson(),
      ),
    );

    final compactJson = jsonEncode({
      'rolling_summary': '前 26 条已压缩成摘要。',
      'entries': [],
    });
    final fakeAi = _FakeAiClient(
      ['好的，继续往下讲。'],
      compactJsonReply: compactJson,
    );

    final container = ProviderContainer(
      overrides: [
        initialStorageRootProvider.overrideWithValue(''),
        fileStoreProvider.overrideWithValue(store),
        aiSettingsProvider.overrideWithValue(
          const AiSettings(enabled: true, autoPlayTts: false),
        ),
        aiApiKeyProvider.overrideWith((ref) async => 'sk-test'),
        aiClientProvider.overrideWithValue(fakeAi),
      ],
    );
    addTearDown(container.dispose);

    final ctrl = container.read(studyChatControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // 1. 执行一次自动窗口压缩（40 条触发，保留最近 14 条在活跃窗口，但全部 40 条留在屏幕）
    final ok = await ctrl.compactAndDistillNow(isAuto: true);
    expect(ok, true);

    final afterCompact = container.read(studyChatControllerProvider);
    expect(afterCompact.conversationalMessages.length, 40);
    expect(afterCompact.activeLlmMessages.length, 14);
    expect(afterCompact.rollingSummary, '前 26 条已压缩成摘要。');

    // 2. 再发一条新提问，验证发给大模型 API 的只有「System + 最近 14 条 + 新提问」，而非 41 条
    await ctrl.sendText('新问题');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(fakeAi.lastStreamMessages, isNotNull);
    // 1 system + 14 recent + 1 new user = 16
    expect(fakeAi.lastStreamMessages!.length, 16);
    expect(fakeAi.lastStreamMessages!.first.content, contains('前 26 条已压缩成摘要'));

    // 3. 验证持久化重新加载后，超过 120 条的极端情况会平滑淘汰最古早条目
    final hugeMsgs = List.generate(
      125,
      (i) => StudyMessage(
        id: 'h-$i',
        role: i.isEven ? StudyMessageRole.user : StudyMessageRole.assistant,
        content: '历史 $i',
        createdAt: DateTime(2026, 11, 20),
      ),
    );
    await store.write(
      AppPaths.conversationFile,
      jsonEncode(
        ConversationMemory(
          messages: hugeMsgs,
          lastDistilledCount: 120,
          updatedAt: DateTime(2026, 11, 20),
        ).toJson(),
      ),
    );
    final container2 = ProviderContainer(
      overrides: [
        initialStorageRootProvider.overrideWithValue(''),
        fileStoreProvider.overrideWithValue(store),
        aiSettingsProvider.overrideWithValue(
          const AiSettings(enabled: true, autoPlayTts: false),
        ),
        aiApiKeyProvider.overrideWith((ref) async => 'sk-test'),
        aiClientProvider.overrideWithValue(fakeAi),
      ],
    );
    addTearDown(container2.dispose);
    final ctrl2 = container2.read(studyChatControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await ctrl2.sendText('第 126 条');
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final capped = container2.read(studyChatControllerProvider);
    expect(capped.conversationalMessages.length, 120);
    expect(capped.conversationalMessages.first.id, isNot('h-0'));
  });
}
