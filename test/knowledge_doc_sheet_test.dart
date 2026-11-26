import 'package:echomind_app/features/learn/widgets/knowledge_doc_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleDocMarkdown = '''
# 编程

## 递归 `2026-11-17`
- 核心：大问题交小一号自身 → 至基线直接答
- 类比：问前排第几排，传至第一排直答
- 误区：误: 一口气追到底 → 实: 信小版本自返
- 复述：先想谁不问，再想怎么问

## 递归的终止条件 `2026-11-18`
- 核心：无基线 → 链条永不收敛 → 栈溢出卡死
- 类比：没人说第一排 → 全在问
- 误区：误: 函数本身就是终点 → 实: 不再追问的情形才是
- 复述：没人喊停，全卡死
''';

void main() {
  testWidgets('专题文档支持复习菜单（遮住答案自测 / AI 抽查）与退出自测状态切换', (tester) async {
    var aiReviewTapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: KnowledgeDocSheet(
          title: '编程',
          subtitle: 'docs/programming.md',
          markdown: _sampleDocMarkdown,
          onReviewPressed: () => aiReviewTapped++,
        ),
      ),
    );

    // 1. 默认卡片全展开，顶栏展示「复习」胶囊
    expect(find.text('递归'), findsOneWidget);
    expect(find.text('复习'), findsOneWidget);
    expect(find.text('大问题交小一号自身 → 至基线直接答'), findsOneWidget);

    // 2. 点击「复习」→ 弹出 2 个清晰选项 → 选择「遮住答案自测」
    await tester.tap(find.byKey(const Key('doc_review_menu_btn')));
    await tester.pumpAndSettle();
    expect(find.text('遮住答案自测'), findsOneWidget);
    expect(find.text('AI 苏格拉底抽查'), findsOneWidget);

    await tester.tap(find.byKey(const Key('review_option_self_test')));
    await tester.pumpAndSettle();

    // 顶栏胶囊切换为「退出自测」，卡片正文被遮挡
    expect(find.text('退出自测'), findsOneWidget);
    expect(find.text('先自己回忆，点一下核对'), findsNWidgets(2));
    expect(find.text('大问题交小一号自身 → 至基线直接答'), findsNothing);

    // 3. 点击第一张卡片展开核对
    await tester.tap(find.byKey(const Key('knowledge_card_0')));
    await tester.pumpAndSettle();
    expect(find.text('大问题交小一号自身 → 至基线直接答'), findsOneWidget);
    expect(find.text('先自己回忆，点一下核对'), findsOneWidget);

    // 4. 点击「退出自测」恢复全部显示
    await tester.tap(find.byKey(const Key('doc_exit_self_test_btn')));
    await tester.pumpAndSettle();
    expect(find.text('复习'), findsOneWidget);
    expect(find.text('无基线 → 链条永不收敛 → 栈溢出卡死'), findsOneWidget);

    // 5. 选择「AI 苏格拉底抽查」触发回调
    await tester.tap(find.byKey(const Key('doc_review_menu_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review_option_ai_socratic')));
    await tester.pumpAndSettle();
    expect(aiReviewTapped, 1);
  });

  testWidgets('大纲与搜索面板支持按正文关键词过滤并点击跳转，更多菜单收纳导出与复制', (tester) async {
    var exported = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: KnowledgeDocSheet(
          title: '编程',
          subtitle: 'docs/programming.md',
          markdown: _sampleDocMarkdown,
          onExportPressed: () => exported++,
        ),
      ),
    );

    // 1. 打开大纲与搜索面板，按正文关键词「栈溢出」筛选
    await tester.tap(find.byKey(const Key('doc_outline_search_btn')));
    await tester.pumpAndSettle();
    expect(find.text('大纲 · 共 2 条'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('doc_outline_search_input')),
      '栈溢出',
    );
    await tester.pumpAndSettle();
    expect(find.text('匹配 1 / 2 条'), findsOneWidget);
    expect(find.byKey(const Key('outline_item_1')), findsOneWidget);
    expect(find.byKey(const Key('outline_item_0')), findsNothing);

    // 点击命中项关闭面板并跳转高亮
    await tester.tap(find.byKey(const Key('outline_item_1')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byKey(const Key('doc_outline_search_input')), findsNothing);

    // 2. 点击「⋯」更多菜单触发导出 Markdown
    await tester.tap(find.byKey(const Key('doc_more_menu_btn')));
    await tester.pumpAndSettle();
    expect(find.text('导出 Markdown'), findsOneWidget);
    expect(find.text('复制 Markdown'), findsOneWidget);

    await tester.tap(find.text('导出 Markdown'));
    await tester.pumpAndSettle();
    expect(exported, 1);
  });

  testWidgets('KNOWLEDGE.md 总索引回退纯 Markdown 渲染，不显示大纲搜索和复习胶囊', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: KnowledgeDocSheet(
          title: '知识沉淀总清单',
          subtitle: 'KNOWLEDGE.md',
          markdown:
              '# KNOWLEDGE.md\n\n## 编程 (`docs/programming.md`)\n- **递归**：大问题交小一号自身',
        ),
      ),
    );

    expect(find.byKey(const Key('doc_outline_search_btn')), findsNothing);
    expect(find.byKey(const Key('doc_review_menu_btn')), findsNothing);
    expect(find.byKey(const Key('doc_more_menu_btn')), findsOneWidget);
    expect(find.textContaining('递归'), findsOneWidget);
  });

  testWidgets('支持编辑 Markdown 保存与删除专题交互', (tester) async {
    String? savedMarkdown;
    var deleted = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: KnowledgeDocSheet(
          title: 'C++',
          subtitle: 'docs/cpp.md',
          markdown: '# C++\n',
          onSaveMarkdown: (updated) async {
            savedMarkdown = updated;
            return true;
          },
          onDeleteDoc: () async {
            deleted++;
            return true;
          },
        ),
      ),
    );

    // 空专题在 Markdown 视图下直接给出「编辑专题内容」按钮
    await tester.tap(find.byKey(const Key('doc_empty_edit_btn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('doc_markdown_editor')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('doc_markdown_editor')),
      '# C++\n\n## 传值 vs 传引用 `2026-11-26`\n- 核心：大对象传引用零拷贝\n',
    );
    await tester.tap(find.byKey(const Key('doc_save_edit_btn')));
    await tester.pumpAndSettle();

    expect(savedMarkdown, contains('大对象传引用零拷贝'));
    expect(find.text('传值 vs 传引用'), findsOneWidget);

    // 通过更多菜单触发删除确认
    await tester.tap(find.byKey(const Key('doc_more_menu_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('doc_delete_menu_item')));
    await tester.pumpAndSettle();

    expect(find.text('删除专题'), findsWidgets);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(deleted, 1);
  });
}
