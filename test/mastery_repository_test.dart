import 'package:echomind_app/data/app_paths.dart';
import 'package:echomind_app/data/repositories/mastery_repository.dart';
import 'package:echomind_app/data/storage/memory_file_store.dart';
import 'package:echomind_app/domain/models/knowledge_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MasteryRepository (mastery/<slug>.json)', () {
    test('支持 MasteryProfile 的保存、读取、列举与删除，并持久化动态路线图', () async {
      final store = MemoryFileStore();
      final repo = MasteryRepository(store);

      final profile = MasteryProfile(
        slug: 'economics',
        subjectName: '经济学与金融',
        targetGoal: '看懂公司财报并分析行业竞争格局',
        level: MasteryLevel.intermediate,
        score: 42,
        confidence: 0.65,
        strengths: const ['供需与价格信号直觉'],
        weaknesses: const ['自由现金流与账面利润混淆'],
        roadmap: const [
          RoadmapNode(
            id: 'n1',
            title: '供需与稀缺性',
            level: MasteryLevel.beginner,
            status: RoadmapNodeStatus.skipped,
            reason: '已有笔记显示已掌握',
          ),
          RoadmapNode(
            id: 'n2',
            title: '利润 vs 自由现金流',
            level: MasteryLevel.intermediate,
            status: RoadmapNodeStatus.active,
            focusGoal: '能独立识别账面盈利但现金流恶化的风险案例',
          ),
        ],
        lastCalibratedCount: 4,
        updatedAt: DateTime(2026, 11, 26),
      );

      await repo.saveProfile(profile);
      expect(
        await store.exists(AppPaths.masteryProfileFile('economics')),
        true,
      );

      final loaded = await repo.loadProfile('economics');
      expect(loaded, isNotNull);
      expect(loaded!.level, MasteryLevel.intermediate);
      expect(loaded.score, 42);
      expect(loaded.activeNode?.id, 'n2');
      expect(loaded.completedNodesCount, 1);

      final all = await repo.loadAllProfiles();
      expect(all.keys, contains('economics'));

      await repo.deleteProfile('economics');
      expect(await repo.loadProfile('economics'), isNull);
    });
  });
}
