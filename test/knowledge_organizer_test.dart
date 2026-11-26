import 'dart:convert';

import 'package:echomind_app/data/ai/ai_client.dart';
import 'package:echomind_app/data/ai/knowledge_organizer.dart';
import 'package:echomind_app/data/app_paths.dart';
import 'package:echomind_app/data/repositories/knowledge_repository.dart';
import 'package:echomind_app/data/storage/memory_file_store.dart';
import 'package:echomind_app/domain/models/ai_settings.dart';
import 'package:echomind_app/features/learn/study_chat_controller.dart';
import 'package:echomind_app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOrganizeAiClient implements AiClient {
  final String jsonReply;
  final List<String> streamDeltas;
  List<AiMessage>? lastChatMessages;

  _FakeOrganizeAiClient(
    this.jsonReply, {
    this.streamDeltas = const [],
  });

  @override
  Future<String> chat(
    List<AiMessage> messages, {
    bool? enableWebSearch,
  }) async {
    lastChatMessages = messages;
    return jsonReply;
  }

  @override
  Stream<AiChunk> streamChat(
    List<AiMessage> messages, {
    bool? enableWebSearch,
  }) async* {
    for (final d in streamDeltas) {
      yield AiChunk(d);
    }
    yield AiChunk.done;
  }

  @override
  Future<void> testConnection() async {}

  @override
  void cancel() {}

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KnowledgeOrganizer 知识库写操作意图识别与执行', () {
    test('精准识别新增/拆分/整理知识库指令，不误伤普通学习提问', () {
      expect(
        KnowledgeOrganizer.looksLikeKnowledgeWriteRequest(
          '我只是想让回响APP，在知识库里新增一个C++的专题而已',
        ),
        true,
      );
      expect(
        KnowledgeOrganizer.looksLikeKnowledgeWriteRequest(
          '把编程与软件里的 C++ 笔记拆成单独的专题',
        ),
        true,
      );
      expect(
        KnowledgeOrganizer.looksLikeKnowledgeWriteRequest(
          '把刚才聊的传引用写进 C++ 专题里',
        ),
        true,
      );

      // 普通学习/复习提问不应触发写操作
      expect(
        KnowledgeOrganizer.looksLikeKnowledgeWriteRequest('我想学一下 C++ 专题'),
        false,
      );
      expect(
        KnowledgeOrganizer.looksLikeKnowledgeWriteRequest('聊聊知识库里的经济学'),
        false,
      );
      expect(
        KnowledgeOrganizer.looksLikeKnowledgeWriteRequest('C++ 传引用为什么省内存？'),
        false,
      );
    });

    test('在对话中直接发出拆分指令时，AI 携带完整 docs/*.md 上下文完成落盘并刷新状态', () async {
      final store = MemoryFileStore();
      final repo = KnowledgeRepository(store);
      await repo.saveDocMarkdown(
        slug: 'programming',
        markdown: '''
# 编程与软件

## 拆解AI代码法 `2026-11-20`
- 核心：整段不懂 → 切最小函数 → 只问输入输出

## 传值 vs 传引用 `2026-11-21`
- 核心：传值整包复印，传引用递地址零拷贝
- 类比：传整本书复印件 vs 直接给书页码
- 误区：误: 所有情况都必须加& → 实: 单int等小包差异不大
''',
      );

      final organizeJson = jsonEncode({
        'upserts': [
          {
            'slug': 'cpp',
            'title': 'C++',
            'markdown':
                '# C++\n\n## 传值 vs 传引用 `2026-11-21`\n- 核心：传值整包复印，传引用递地址零拷贝\n- 类比：传整本书复印件 vs 直接给书页码\n- 误区：误: 所有情况都必须加& → 实: 单int等小包差异不大',
          },
          {
            'slug': 'programming',
            'title': '编程与软件',
            'markdown':
                '# 编程与软件\n\n## 拆解AI代码法 `2026-11-20`\n- 核心：整段不懂 → 切最小函数 → 只问输入输出',
          },
        ],
        'deletes': [],
        'reply': '已经建好 C++ 专题，把原来在编程与软件里的传值 vs 传引用笔记完整拆过去了。你想接着聊哪个 C++ 问题？',
      });

      final fakeAi = _FakeOrganizeAiClient(organizeJson);
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

      // 等待异步 hydrate 完成
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final ctrl = container.read(studyChatControllerProvider.notifier);

      await ctrl.sendText('把编程与软件里的 C++ 拆出去，在知识库新增一个 C++ 专题');

      // 确认模型看到了完整 docs/programming.md 原文（含类比与误区）
      final userPrompt = fakeAi.lastChatMessages!.last.content;
      expect(userPrompt, contains('传整本书复印件 vs 直接给书页码'));

      final after = container.read(studyChatControllerProvider);
      expect(after.knowledgeDocs.map((d) => d.slug), containsAll(['cpp', 'programming']));
      expect(after.knowledgeIndex, contains('## C++ (`docs/cpp.md`)'));
      expect(await store.exists(AppPaths.knowledgeDocFile('cpp')), true);

      final cppDoc = await repo.readDocMarkdown('cpp');
      expect(cppDoc, contains('- 类比：传整本书复印件 vs 直接给书页码'));

      final progDoc = await repo.readDocMarkdown('programming');
      expect(progDoc, contains('拆解AI代码法'));
      expect(progDoc, isNot(contains('传值 vs 传引用')));
    });

    test('手动 distillNow 只沉淀知识到文档与索引，完整保留对话框历史消息不折叠清空', () async {
      final store = MemoryFileStore();
      final distillJson = jsonEncode({
        'rolling_summary': '',
        'entries': [
          {
            'category_slug': 'cpp',
            'category_name': 'C++',
            'topic': '引用传参',
            'one_liner': '形参加&递地址，零拷贝且可改实参',
            'analogy': '直接给页码而非复印整本书',
            'misconception': '',
            'feynman_note': '加&就是直接改原件',
          },
        ],
      });
      final fakeAi = _FakeOrganizeAiClient(
        distillJson,
        streamDeltas: const ['参数加了 & 之后直接指向原变量，你想想为什么不会产生整包拷贝？'],
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

      await ctrl.sendText('什么是 C++ 引用传参？');
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final beforeCount =
          container.read(studyChatControllerProvider).messages.length;
      expect(beforeCount, greaterThanOrEqualTo(2));

      final distilledCount = await ctrl.distillNow();
      expect(distilledCount, 1);

      final after = container.read(studyChatControllerProvider);
      expect(after.messages.length, beforeCount);
      expect(after.knowledgeIndex, contains('引用传参'));
      expect(await store.exists(AppPaths.knowledgeDocFile('cpp')), true);
    });
  });
}
