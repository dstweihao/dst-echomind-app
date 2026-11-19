import 'package:echomind_app/data/ai/prompts/study_mode_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

import 'prompt_quality_evaluator.dart';

void main() {
  group('Prompt 质量防线 1：系统提示词静态结构与去 AI 味约束', () {
    test('系统提示词完整满足四大教学原则与去 AI 味规范', () {
      final issues = PromptSystemRuleValidator.validateSystemPrompt(
        StudyModePrompt.systemPrompt,
      );
      expect(
        issues,
        isEmpty,
        reason: '系统提示词应通过所有静态规范校验，实际未通过项: $issues',
      );
    });

    test('系统提示词不得包含 3d6f0e8 引入的劣质模式（死板实物限制、违禁口癖、剧透解析）', () {
      const prompt = StudyModePrompt.systemPrompt;

      // 负向断言：防死板实体强加
      expect(
        prompt.contains('必须且只能包含生活物理实体'),
        isFalse,
        reason: '严禁强制限制实物实体，避免概念解释削足适履',
      );
      expect(
        prompt.contains('水龙头、快递盒、柜台排队、借条、钥匙、收纳盒'),
        isFalse,
        reason: '严禁硬编码窄化实物列表',
      );

      // 负向断言：防口癖注入
      expect(
        prompt.contains('咱先不管') || prompt.contains('咱拿'),
        isFalse,
        reason: '提示词中严禁出现“咱”等轻浮口癖示范',
      );

      // 负向断言：防括号解析示范外泄
      expect(
        prompt.contains('（正确原因：') || prompt.contains('（错误原因：'),
        isFalse,
        reason: '提示词范例严禁使用括号元解析，避免模型模仿带括号剧透',
      );
    });

    test('buildSystemPrompt 注入动态上下文后仍保持结构纯正', () {
      final promptWithContext = StudyModePrompt.buildSystemPrompt(
        knowledgeIndex: '- **递归**：大问题拆解成小问题',
        rollingSummary: '上一轮讨论了数列递推。',
        focusedDocTitle: '算法基础',
        focusedDocContent: '## 递归与分治',
        webSearchEnabled: true,
      );

      final issues = PromptSystemRuleValidator.validateSystemPrompt(
        promptWithContext,
      );
      expect(issues, isEmpty);
      expect(promptWithContext, contains('联网核实能力（已开启）'));
      expect(promptWithContext, contains('用户已沉淀的知识地图（KNOWLEDGE.md）'));
    });
  });

  group('Prompt 质量防线 2：Commit 3d6f0e8 历史坏样本精准拦截 (Regression Eval)', () {
    test('精准拦截「第一性原理」强套快递盒与“咱”口癖输出', () {
      // 3d6f0e8 线上真实产出的恶性样例
      const badResponse =
          '先不管这个词听着多高级，咱拿快递盒打个比方。假设你收到一个装满乱七八糟旧东西的箱子，如果你想重新整理，最彻底的办法是不是把里面的东西全倒出来，一件一件看？把箱子倒空这一步最难的地方在哪儿？';

      final result = PromptQualityEvaluator.evaluateResponse(
        concept: '第一性原理',
        response: badResponse,
        turn: 1,
      );

      expect(result.passed, isFalse);
      expect(
        result.hasViolation(PromptViolationCategory.forbiddenMannerism),
        isTrue,
        reason: '应捕获“咱”及“先不管这个词听着多高级”',
      );
      expect(
        result.hasViolation(PromptViolationCategory.rigidEntityAnalogy),
        isTrue,
        reason: '应捕获为第一性原理强加“快递盒/装满乱七八糟旧东西的箱子”',
      );
    });

    test('精准拦截「杰文斯悖论」括号自加剧透输出', () {
      // 3d6f0e8 线上真实产出的恶性样例（自加括号剧透并泄露核心机制）
      const badResponse =
          '假设原来每辆蒸汽机车烧 10 吨煤跑 100 公里，后来发明了新技术，只要 2 吨煤就能跑 100 公里。按常理讲，全国消耗的总煤炭应该减少，但为什么最后全英国的煤反而被挖得更多、烧得更快了？（其实就是因为用煤成本大跌，导致所有人都在疯狂买蒸汽机，总需求反弹了，这就是杰文斯悖论）';

      final result = PromptQualityEvaluator.evaluateResponse(
        concept: '杰文斯悖论',
        response: badResponse,
        turn: 1,
      );

      expect(result.passed, isFalse);
      expect(
        result.hasViolation(PromptViolationCategory.spoilerParentheses),
        isTrue,
        reason: '应捕获尾部括号内的自作聪明剧透与底牌揭晓',
      );
    });

    test('精准拦截「递归」的虚伪夸奖、首轮掀底牌、连珠炮审讯与八股标题', () {
      const badResponse =
          '问得好！你一下就抓到本质了！递归其实就是函数在内部调用自己。那么问题来了：你在两面镜子中间看到过无限重叠的自己吗？如果镜子碎了会怎样？那你觉得终止条件该写在哪？【核心原理】就是不断压栈。';

      final result = PromptQualityEvaluator.evaluateResponse(
        concept: '递归',
        response: badResponse,
        turn: 1,
      );

      expect(result.passed, isFalse);
      expect(
        result.hasViolation(PromptViolationCategory.flatteryCliche),
        isTrue,
      );
      expect(
        result.hasViolation(PromptViolationCategory.prematureAnswerDump),
        isTrue,
      );
      expect(
        result.hasViolation(PromptViolationCategory.interrogationOverload),
        isTrue,
      );
      expect(
        result.hasViolation(PromptViolationCategory.roboticFormatting),
        isTrue,
      );
    });

    test('精准拦截「闭包」的教科书倒灌与括号自解', () {
      const badResponse =
          '闭包（Closure）是指有权访问另一个函数作用域中的变量的函数。创建闭包的常见方式是在一个函数内部创建另一个函数。（原理就是词法作用域保留自由变量）你觉得呢？';

      final result = PromptQualityEvaluator.evaluateResponse(
        concept: '闭包',
        response: badResponse,
        turn: 1,
      );

      expect(result.passed, isFalse);
      expect(
        result.hasViolation(PromptViolationCategory.prematureAnswerDump),
        isTrue,
      );
      expect(
        result.hasViolation(PromptViolationCategory.spoilerParentheses),
        isTrue,
      );
    });
  });

  group('Prompt 质量防线 3：典型抽象概念标杆正例离线评估 (Golden Benchmark)', () {
    test('「第一性原理」黄金正例应完全通过质检', () {
      const goldenResponse =
          '如果想造一台便宜好用的电动车，但市面上现成的电池包太贵，大部分人会觉得这事没法做。如果顺着底层往回推，电池到底是由什么最基础的原材料构成的？';

      final result = PromptQualityEvaluator.evaluateResponse(
        concept: '第一性原理',
        response: goldenResponse,
        turn: 1,
      );

      expect(
        result.passed,
        isTrue,
        reason: '标杆正例不应触发任何违规：${result.summary()}',
      );
      expect(result.violations, isEmpty);
    });

    test('「杰文斯悖论」黄金正例应完全通过质检', () {
      const goldenResponse =
          '看一个日常生活现象：以前燃油车每公里油费 1 块钱，不少人周末舍不得开车出门；后来换了电车，每公里电费只要 1 毛钱。你猜猜大家每个月开车的总里程，一般会发生什么变化？';

      final result = PromptQualityEvaluator.evaluateResponse(
        concept: '杰文斯悖论',
        response: goldenResponse,
        turn: 1,
      );

      expect(
        result.passed,
        isTrue,
        reason: '标杆正例不应触发任何违规：${result.summary()}',
      );
      expect(result.violations, isEmpty);
    });

    test('「递归」黄金正例应完全通过质检', () {
      const goldenResponse =
          '假如你在电影院排队买票，前面排了很长一队，你看不见最前面。如果你只能问你前面紧挨着的那个人“你是第几位”，这个人会怎么帮你问出答案？';

      final result = PromptQualityEvaluator.evaluateResponse(
        concept: '递归',
        response: goldenResponse,
        turn: 1,
      );

      expect(
        result.passed,
        isTrue,
        reason: '标杆正例不应触发任何违规：${result.summary()}',
      );
      expect(result.violations, isEmpty);
    });

    test('「闭包」黄金正例应完全通过质检', () {
      const goldenResponse =
          '平时函数运行完，里面的局部变量就随风消散了。但如果一个背包被悄悄留给了内部的一个小助手，外部的人虽然碰不到这个背包，但只要呼叫小助手，小助手还能继续从背包里拿东西。你觉得为什么这个背包没有被系统清理掉？';

      final result = PromptQualityEvaluator.evaluateResponse(
        concept: '闭包',
        response: goldenResponse,
        turn: 1,
      );

      expect(
        result.passed,
        isTrue,
        reason: '标杆正例不应触发任何违规：${result.summary()}',
      );
      expect(result.violations, isEmpty);
    });
  });

  group('Prompt 质量防线 4：细粒度断言规则专项边界测试', () {
    test('合法学术或说明性括号不应被误判为剧透括号', () {
      const harmlessBracketResponse =
          '电池由正极、负极材料（比如锂、镍、石墨）以及电解液组成。如果直接去大宗商品市场买这些原材料，总成本大概是多少？';

      final violations = PromptQualityEvaluator.checkSpoilerParentheses(
        '第一性原理',
        harmlessBracketResponse,
      );
      expect(violations, isEmpty, reason: '材料列举类客观括号不应触发剧透误判');
    });

    test('单轮未以反问句收尾时应正确告警', () {
      const noEndQuestionResponse =
          '如果直接从源头计算原材料成本，我们就能知道电池底价是多少。这一步需要掌握基本的物理化学知识。';

      final violations = PromptQualityEvaluator.checkQuestionScaffold(
        noEndQuestionResponse,
      );
      expect(
        violations.any(
          (v) => v.category == PromptViolationCategory.missingQuestion,
        ),
        isTrue,
      );
    });

    test('单轮连珠炮提问应触发超载告警', () {
      const multiQuestions =
          '你觉得原材料贵不贵？如果很便宜那是为什么？是不是加工工艺有问题？那我们要怎么改造生产线？';

      final violations = PromptQualityEvaluator.checkQuestionScaffold(
        multiQuestions,
      );
      expect(
        violations.any(
          (v) => v.category == PromptViolationCategory.interrogationOverload,
        ),
        isTrue,
      );
    });

    test('篇幅超出语音朗读舒适区间应触发告警', () {
      final tooLong = '这个原理非常有趣。' * 50; // 450 字，超过 380 字
      final violations = PromptQualityEvaluator.checkFormattingAndLength(
        tooLong,
      );
      expect(
        violations.any(
          (v) => v.category == PromptViolationCategory.lengthOutOfRange,
        ),
        isTrue,
      );
    });
  });
}
