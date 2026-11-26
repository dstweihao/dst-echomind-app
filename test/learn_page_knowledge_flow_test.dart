import 'dart:convert';

import 'package:echomind_app/data/ai/ai_client.dart';
import 'package:echomind_app/data/app_paths.dart';
import 'package:echomind_app/data/repositories/knowledge_repository.dart';
import 'package:echomind_app/data/storage/memory_file_store.dart';
import 'package:echomind_app/domain/models/ai_settings.dart';
import 'package:echomind_app/features/learn/learn_page.dart';
import 'package:echomind_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _WidgetFakeAiClient implements AiClient {
  final List<String> streamReplies;
  final String chatReply;

  _WidgetFakeAiClient({
    required this.streamReplies,
    required this.chatReply,
  });

  @override
  Stream<AiChunk> streamChat(
    List<AiMessage> messages, {
    bool? enableWebSearch,
  }) async* {
    for (final chunk in streamReplies) {
      yield AiChunk(chunk);
    }
    yield AiChunk.done;
  }

  @override
  Future<String> chat(
    List<AiMessage> messages, {
    bool? enableWebSearch,
  }) async =>
      chatReply;

  @override
  Future<void> testConnection() async {}

  @override
  void cancel() {}

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('端到端UI流程：抽屉新建C++专题 + 代码块对话 + 手动沉淀保留历史 + 抽屉AI整理', (tester) async {
    final store = MemoryFileStore();
    final repo = KnowledgeRepository(store);
    await repo.saveDocMarkdown(
      slug: 'programming',
      markdown: '''
# 编程与软件

## 拆解AI代码法 `2026-11-20`
- 核心：整段不懂 → 切最小函数 → 只问输入输出
''',
    );

    final chatJson = jsonEncode({
      'rolling_summary': '',
      'entries': [
        {
          'category_slug': 'cpp',
          'category_name': 'C++',
          'topic': '引用别名',
          'one_liner': 'int& r = a 绑定原变量，零拷贝直接修改实参',
          'analogy': '给同一张桌子起外号',
          'misconception': '',
          'feynman_note': '加&就是改本尊',
        },
      ],
      'upserts': [
        {
          'slug': 'cpp',
          'title': 'C++',
          'markdown': '# C++\n\n## 引用别名 `2026-11-26`\n- 核心：int& r = a 绑定原变量，零拷贝直接修改实参',
        },
      ],
      'deletes': [],
      'reply': '已帮你把 C++ 专题整理好了，接下来想先看哪一条？',
    });

    final fakeAi = _WidgetFakeAiClient(
      streamReplies: const [
        '看下面这段最小对比：\n\n```cpp\nvoid add(int& x) { x += 1; }\n```\n\n加了 `&` 之后，函数里改 `x` 会影响外面的变量吗？',
      ],
      chatReply: chatJson,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialStorageRootProvider.overrideWithValue(''),
          fileStoreProvider.overrideWithValue(store),
          aiSettingsProvider.overrideWithValue(
            const AiSettings(enabled: true, autoPlayTts: false),
          ),
          aiApiKeyProvider.overrideWith((ref) async => 'sk-test'),
          aiClientProvider.overrideWithValue(fakeAi),
        ],
        child: const MaterialApp(home: LearnPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 打开左侧知识库抽屉，点击「+ 新建」创建 C++ 专题
    await tester.tap(find.byTooltip('个人知识沉淀库 (KNOWLEDGE.md & docs/)'));
    await tester.pumpAndSettle();

    expect(find.text('编程与软件'), findsOneWidget);
    await tester.tap(find.byKey(const Key('drawer_new_topic_btn')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('create_topic_title_input')),
      'C++',
    );
    await tester.pumpAndSettle();
    // 验证自动推导的 slug 为 cpp
    expect(find.text('cpp'), findsOneWidget);

    await tester.tap(find.byKey(const Key('create_topic_confirm_btn')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 自动打开新建专题页
    expect(find.text('docs/cpp.md'), findsOneWidget);
    expect(await store.exists(AppPaths.knowledgeDocFile('cpp')), true);

    // 返回主对话页
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    // 2. 在对话中提问并渲染 ```cpp 代码块
    await tester.enterText(find.byType(TextField).last, '讲讲 C++ 引用');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(find.text('讲讲 C++ 引用'), findsOneWidget);
    expect(find.textContaining('void add(int& x)'), findsOneWidget);

    // 3. 点击顶栏「沉淀」按钮，验证写入知识库且对话气泡一条不丢
    await tester.tap(find.byTooltip('沉淀到知识库（保留对话）'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('讲讲 C++ 引用'), findsOneWidget);
    expect(find.textContaining('void add(int& x)'), findsOneWidget);
    expect(await repo.readIndexMarkdown(), contains('引用别名'));

    // 4. 打开抽屉点击「整理」触发 AI 整理弹窗
    await tester.tap(find.byTooltip('个人知识沉淀库 (KNOWLEDGE.md & docs/)'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('drawer_organize_btn')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('organize_kb_instruction_input')),
      '把 C++ 整理成独立专题',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('organize_kb_confirm_btn')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('已帮你把 C++ 专题整理好了'), findsOneWidget);
  });
}
