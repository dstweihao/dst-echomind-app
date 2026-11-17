import 'package:echomind_app/data/app_paths.dart';
import 'package:echomind_app/data/repositories/knowledge_repository.dart';
import 'package:echomind_app/data/storage/memory_file_store.dart';
import 'package:echomind_app/domain/models/knowledge_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KnowledgeRepository (KNOWLEDGE.md + docs/<slug>.md)', () {
    test('增量追加写入 docs/<slug>.md 不覆盖旧内容，并自动重建 KNOWLEDGE.md 总清单', () async {
      final store = MemoryFileStore();
      final repo = KnowledgeRepository(store);

      // 第 1 次沉淀：经济学 - 通货膨胀
      await repo.appendEntries([
        KnowledgeEntry(
          categorySlug: 'economics',
          categoryName: '经济学与金融',
          topic: '通货膨胀',
          oneLiner: '商品总量不变但货币变多，导致单位货币购买力下降。',
          analogy: '小岛 10 个苹果，钱从 100 变 200，苹果从 10 块涨到 20 块。',
          misconception: '误以为只是个别商品涨价。',
          feynmanNote: '钱变多、东西没变多，钱就不值钱了。',
          createdAt: DateTime(2026, 11, 17),
        ),
      ]);

      // 第 2 次沉淀：同类别追加“量化宽松” + 新类别“编程思维 - 递归”
      await repo.appendEntries([
        KnowledgeEntry(
          categorySlug: 'economics',
          categoryName: '经济学与金融',
          topic: '量化宽松',
          oneLiner: '央行通过购买债券向市场直接注入流动性。',
          createdAt: DateTime(2026, 11, 17),
        ),
        KnowledgeEntry(
          categorySlug: 'Programming & CS!',
          categoryName: '编程与计算机',
          topic: '递归',
          oneLiner: '函数调用自身，靠终止条件把大问题拆成同构小问题。',
          analogy: '一层层打开俄罗斯套娃，见到最小的再依次合回去。',
          createdAt: DateTime(2026, 11, 17),
        ),
      ]);

      // 验证 docs/economics.md 两条都在，未覆盖旧内容，且采用高信息密度紧凑格式
      final econDoc = await repo.readDocMarkdown('economics');
      expect(econDoc, contains('# 经济学与金融'));
      expect(econDoc, contains('## 通货膨胀 `2026-11-17`'));
      expect(econDoc, contains('- 核心：商品总量不变但货币变多'));
      expect(econDoc, contains('## 量化宽松 `2026-11-17`'));
      expect(econDoc, isNot(contains('俄罗斯套娃')));

      // 验证非法字符 slug 被安全规范化
      final progDoc = await repo.readDocMarkdown('programming-cs');
      expect(progDoc, contains('# 编程与计算机'));
      expect(progDoc, contains('## 递归'));

      // 验证总清单 KNOWLEDGE.md 包含全部类别与条目索引
      final index = await repo.readIndexMarkdown();
      expect(index, contains('KNOWLEDGE.md'));
      expect(index, contains('## 经济学与金融 (`docs/economics.md`)'));
      expect(index, contains('- **通货膨胀**：商品总量不变但货币变多'));
      expect(index, contains('- **量化宽松**：央行通过购买债券'));
      expect(index, contains('## 编程与计算机 (`docs/programming-cs.md`)'));
      expect(index, contains('- **递归**：函数调用自身'));

      // 验证目录列表元数据与只增不删持久化
      final docs = await repo.listDocs();
      expect(docs.length, 2);
      final econMeta = docs.firstWhere((d) => d.slug == 'economics');
      expect(econMeta.categoryName, '经济学与金融');
      expect(econMeta.entryCount, 2);
      expect(await store.exists(AppPaths.knowledgeIndexFile), true);
      expect(await store.exists(AppPaths.knowledgeDocFile('economics')), true);
      expect(await store.exists(AppPaths.knowledgeDocFile('programming-cs')), true);
    });
  });
}
