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
  testWidgets('专题文档渲染结构化轻卡片，支持遮住答案自测与点击单卡核对', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: KnowledgeDocSheet(
          title: '编程',
          subtitle: 'docs/programming.md',
          markdown: _sampleDocMarkdown,
        ),
      ),
    );

    // 默认卡片全展开
    expect(find.text('递归'), findsOneWidget);
    expect(find.text('递归的终止条件'), findsOneWidget);
    expect(find.text('核心'), findsNWidgets(2));
    expect(find.text('大问题交小一号自身 → 至基线直接答'), findsOneWidget);

    // 点击顶栏眼睛图标进入「遮住答案自测」模式
    await tester.tap(find.byKey(const Key('doc_self_test_toggle_btn')));
    await tester.pumpAndSettle();

    expect(find.text('先自己回忆，点一下核对'), findsNWidgets(2));
    expect(find.text('大问题交小一号自身 → 至基线直接答'), findsNothing);

    // 点击第一张卡片展开核对，第二张保持遮挡
    await tester.tap(find.byKey(const Key('knowledge_card_0')));
    await tester.pumpAndSettle();

    expect(find.text('大问题交小一号自身 → 至基线直接答'), findsOneWidget);
    expect(find.text('先自己回忆，点一下核对'), findsOneWidget);

    // 再次点击眼睛图标恢复全部显示
    await tester.tap(find.byKey(const Key('doc_self_test_toggle_btn')));
    await tester.pumpAndSettle();

    expect(find.text('先自己回忆，点一下核对'), findsNothing);
    expect(find.text('无基线 → 链条永不收敛 → 栈溢出卡死'), findsOneWidget);
  });

  testWidgets('KNOWLEDGE.md 总索引回退纯 Markdown 渲染，不显示闪卡自测开关', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: KnowledgeDocSheet(
          title: '知识沉淀总清单',
          subtitle: 'KNOWLEDGE.md',
          markdown: '# KNOWLEDGE.md\n\n## 编程 (`docs/programming.md`)\n- **递归**：大问题交小一号自身',
        ),
      ),
    );

    expect(find.byKey(const Key('doc_self_test_toggle_btn')), findsNothing);
    expect(find.textContaining('递归'), findsOneWidget);
  });
}
