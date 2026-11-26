import 'dart:convert';

import 'package:echomind_app/data/ai/ai_client.dart';
import 'package:echomind_app/data/ai/mastery_calibrator.dart';
import 'package:echomind_app/data/ai/prompts/study_mode_prompt.dart';
import 'package:echomind_app/data/app_paths.dart';
import 'package:echomind_app/data/storage/memory_file_store.dart';
import 'package:echomind_app/domain/ai_enums_bridge.dart';
import 'package:echomind_app/domain/models/ai_settings.dart';
import 'package:echomind_app/domain/models/knowledge_models.dart';
import 'package:echomind_app/features/learn/study_chat_controller.dart';
import 'package:echomind_app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'data/ai/prompts/prompt_quality_evaluator.dart';

class _MasteryFakeAiClient implements AiClient {
  final String Function(List<AiMessage> messages) onChat;
  final List<String> streamDeltas;
  List<AiMessage>? lastStreamMessages;
  List<AiMessage>? lastChatMessages;

  _MasteryFakeAiClient({
    required this.onChat,
    this.streamDeltas = const [],
  });

  @override
  Future<String> chat(
    List<AiMessage> messages, {
    bool? enableWebSearch,
  }) async {
    lastChatMessages = messages;
    return onChat(messages);
  }

  @override
  Stream<AiChunk> streamChat(
    List<AiMessage> messages, {
    bool? enableWebSearch,
  }) async* {
    lastStreamMessages = messages;
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

  group('MasteryCalibrator 通用自适应精通引擎', () {
    test('精准识别任意学科的“从入门到专家”系统学习请求，不误伤普通提问', () {
      expect(
        MasteryCalibrator.looksLikeStartMasteryRequest('我想系统学习经济学到高级水平'),
        true,
      );
      expect(
        MasteryCalibrator.looksLikeStartMasteryRequest('带我从零到专家学透 C++'),
        true,
      );
      expect(
        MasteryCalibrator.looksLikeStartMasteryRequest('帮我规划一个项目管理的进阶路线'),
        true,
      );
      expect(
        MasteryCalibrator.looksLikeStartMasteryRequest('飞机是怎么飞起来的？'),
        false,
      );
    });

    test('支持任意非编程学科（如经济学）生成 80/20 路线图、跳过已会、动态升级并注入分阶提示词', () async {
      final calibrator = const MasteryCalibrator();

      final initJson = jsonEncode({
        'slug': 'economics',
        'subject_name': '经济学与金融',
        'target_goal': '独立看懂公司财报并分析行业竞争格局',
        'level': 'beginner',
        'score': 20,
        'confidence': 0.5,
        'strengths': ['供需决定价格'],
        'weaknesses': ['利润与现金流差异'],
        'roadmap': [
          {
            'id': 'n1',
            'title': '供需基本直觉',
            'level': 'beginner',
            'status': 'skipped',
            'focus_goal': '理解价格信号',
            'reason': '已有笔记显示已掌握',
          },
          {
            'id': 'n2',
            'title': '利润 vs 自由现金流',
            'level': 'intermediate',
            'status': 'active',
            'focus_goal': '识别账面盈利但现金流失血的企业陷阱',
          },
          {
            'id': 'n3',
            'title': '资本结构与护城河权衡',
            'level': 'expert',
            'status': 'pending',
            'focus_goal': '多维度权衡杠杆风险与扩张回报',
          },
        ],
      });

      final client = _MasteryFakeAiClient(onChat: (_) => initJson);
      final profile = await calibrator.generateInitialRoadmap(
        aiClient: client,
        subjectName: '经济学与金融',
        targetGoal: '看懂公司财报',
        existingDocMarkdown: '# 经济学与金融\n\n## 供需关系\n- 核心：供小于求则涨价',
      );

      expect(profile.slug, 'economics');
      expect(profile.activeNode?.id, 'n2');
      expect(profile.roadmap.first.status, RoadmapNodeStatus.skipped);

      // 验证注入 StudyModePrompt 后仍完全符合去 AI 味静态红线
      final sysPrompt = StudyModePrompt.buildSystemPrompt(
        activeMasteryProfile: profile,
      );
      expect(PromptSystemRuleValidator.validateSystemPrompt(sysPrompt), isEmpty);
      expect(sysPrompt, contains('利润 vs 自由现金流'));
      expect(sysPrompt, contains('供需决定价格'));
      expect(sysPrompt, contains('内部动态路线全貌'));
      expect(sysPrompt, contains('若用户主动询问'));

      // 模拟两轮出色回答后静默校准：跃迁至 L3 高级并推进到 n3
      final calJson = jsonEncode({
        'level': 'advanced',
        'score': 74,
        'confidence': 0.8,
        'strengths': ['供需决定价格', '精准拆穿应收账款虚增利润陷阱'],
        'weaknesses': ['资本周期与护城河取舍'],
        'roadmap': [
          {
            'id': 'n1',
            'title': '供需基本直觉',
            'level': 'beginner',
            'status': 'skipped',
          },
          {
            'id': 'n2',
            'title': '利润 vs 自由现金流',
            'level': 'intermediate',
            'status': 'mastered',
          },
          {
            'id': 'n3',
            'title': '资本结构与护城河权衡',
            'level': 'expert',
            'status': 'active',
          },
        ],
        'notice_text': '已掌握现金流识别，推进至护城河权衡',
      });

      final calClient = _MasteryFakeAiClient(onChat: (_) => calJson);
      final outcome = await calibrator.calibrateFromRecentTurns(
        aiClient: calClient,
        currentProfile: profile,
        recentMessages: [
          StudyMessage(
            id: '1',
            role: StudyMessageRole.user,
            content: '净利润高但应收账款暴增、经营现金流为负，说明利润只是纸面富贵，钱没收回来。',
            createdAt: DateTime(2026, 11, 26),
          ),
        ],
        currentTotalConversationalCount: 4,
      );

      expect(outcome.levelChanged, true);
      expect(outcome.profile.level, MasteryLevel.advanced);
      expect(outcome.profile.score, 74);
      expect(outcome.profile.activeNode?.id, 'n3');
    });

    test('在 StudyChatController 中实现用户完全无感的开局建图 + 每 2 轮后台静默水平校准', () async {
      final store = MemoryFileStore();
      var chatCalls = 0;

      final initJson = jsonEncode({
        'slug': 'management',
        'subject_name': '技术团队管理',
        'target_goal': '从零带好研发团队到成熟管理者',
        'level': 'beginner',
        'score': 20,
        'confidence': 0.4,
        'strengths': [],
        'weaknesses': ['授权与微管理边界'],
        'roadmap': [
          {
            'id': 'm1',
            'title': '任务拆解与有效授权',
            'level': 'beginner',
            'status': 'active',
            'focus_goal': '区分把事做完和把人带出来',
          },
          {
            'id': 'm2',
            'title': '跨部门目标冲突权衡',
            'level': 'advanced',
            'status': 'pending',
          },
        ],
      });

      final calJson = jsonEncode({
        'level': 'intermediate',
        'score': 55,
        'confidence': 0.75,
        'strengths': ['能用验收标准替代盯细节'],
        'weaknesses': ['跨部门冲突权衡'],
        'roadmap': [
          {
            'id': 'm1',
            'title': '任务拆解与有效授权',
            'level': 'beginner',
            'status': 'mastered',
          },
          {
            'id': 'm2',
            'title': '跨部门目标冲突权衡',
            'level': 'advanced',
            'status': 'active',
          },
        ],
        'notice_text': '',
      });

      final fakeAi = _MasteryFakeAiClient(
        streamDeltas: const ['如果你既要保进度又怕新人出错，授权时最该盯住哪一个环节？'],
        onChat: (_) {
          chatCalls++;
          return chatCalls == 1 ? initJson : calJson;
        },
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

      // 第 1 轮：明确开启某专业系统学习，后台静默生成画像，UI 不插入打扰提示
      await ctrl.sendText('我想系统学习技术团队管理到专家水平');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final afterTurn1 = container.read(studyChatControllerProvider);
      expect(afterTurn1.activeMastery?.slug, 'management');
      expect(afterTurn1.activeMastery?.level, MasteryLevel.beginner);
      expect(fakeAi.lastStreamMessages!.first.content, contains('任务拆解与有效授权'));
      expect(afterTurn1.messages.where((m) => m.isCompactionNotice), isEmpty);

      // 第 2 轮：凑满 4 条对话，后台无感触发校准并升级至 L2 + 切换下一关
      await ctrl.sendText('我会先对齐目标和验收底线，中间只约关键里程碑检查，不插手每行代码怎么写。');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final afterTurn2 = container.read(studyChatControllerProvider);
      expect(afterTurn2.activeMastery?.level, MasteryLevel.intermediate);
      expect(afterTurn2.activeMastery?.activeNode?.id, 'm2');
      // 整个过程用户无感：无弹窗、无额外通知条
      expect(afterTurn2.messages.where((m) => m.isCompactionNotice), isEmpty);
      expect(
        await store.exists(AppPaths.masteryProfileFile('management')),
        true,
      );
    });
  });
}
