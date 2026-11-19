/// 提示词质量评估与反剧透质检层 (Prompt Quality Evaluator)
///
/// 专为 EchoMind 苏格拉底学习模式构建的自动化验证与静态断言防线。
/// 覆盖：
/// 1. 违禁口癖与轻浮套话检测（如“咱”、“先不管这个词听着多高级”）；
/// 2. 死板实物强行类比检测（如为哲学/元认知概念强行塞入“快递盒”、“水龙头”）；
/// 3. 违背苏格拉底原则的剧透括号与括号式元解释检测；
/// 4. 首轮提前掀底牌/倒灌教科书定义检测；
/// 5. 单一聚焦反诘与脚手架提问规范；
/// 6. 语音朗读友好与去 AI 味排版规范。
class PromptQualityEvaluator {
  PromptQualityEvaluator._();

  /// 针对抽象概念的 AI 回复进行离线质量评估
  static PromptEvalResult evaluateResponse({
    required String concept,
    required String response,
    int turn = 1,
  }) {
    final violations = <PromptEvalViolation>[];

    violations.addAll(checkForbiddenMannerisms(response));
    violations.addAll(checkFlatteryAndCliches(response));
    violations.addAll(checkSpoilerParentheses(concept, response));
    violations.addAll(checkRigidEntityAnalogy(concept, response));
    violations.addAll(checkPrematureAnswerDump(concept, response, turn: turn));
    violations.addAll(checkQuestionScaffold(response));
    violations.addAll(checkFormattingAndLength(response));

    return PromptEvalResult(
      concept: concept,
      response: response,
      violations: violations,
    );
  }

  /// 1. 检测违禁口癖与轻浮套话
  static List<PromptEvalViolation> checkForbiddenMannerisms(String text) {
    final violations = <PromptEvalViolation>[];

    // 检测轻浮口癖“咱”/“咱们”
    final zanRegex = RegExp(r'咱(?:们|先|来|拿)?');
    final zanMatch = zanRegex.firstMatch(text);
    if (zanMatch != null) {
      violations.add(PromptEvalViolation(
        category: PromptViolationCategory.forbiddenMannerism,
        ruleName: 'forbidden_colloquialism_zan',
        message: '包含过于轻浮/地域化的口癖“咱/咱们”，违背平实自然的真朋友导师语调',
        matchedSnippet: zanMatch.group(0),
      ));
    }

    // 检测傲慢或贬损术语的过渡套话
    final patronizingRegex = RegExp(
      r'(?:先不管(?:这|那)个词(?:听着)?多高级|不用管那些高大上的名词|说白了就是|懂的都懂|其实很简单)',
    );
    final patMatch = patronizingRegex.firstMatch(text);
    if (patMatch != null) {
      violations.add(PromptEvalViolation(
        category: PromptViolationCategory.forbiddenMannerism,
        ruleName: 'patronizing_filler_phrases',
        message: '包含“先不管这个词听着多高级”等假平民套话，缺乏对知识的敬畏与真诚',
        matchedSnippet: patMatch.group(0),
      ));
    }

    return violations;
  }

  /// 2. 检测虚伪夸夸腔（去 AI 味铁律）
  static List<PromptEvalViolation> checkFlatteryAndCliches(String text) {
    final violations = <PromptEvalViolation>[];

    final flatteryRegex = RegExp(
      r'(?:问得好|你这个问题太棒了|太棒了|完全正确|非常深刻|你一下就抓到本质了|你真聪明)[！!.,，]?',
    );
    final match = flatteryRegex.firstMatch(text);
    if (match != null) {
      violations.add(PromptEvalViolation(
        category: PromptViolationCategory.flatteryCliche,
        ruleName: 'no_fake_flattery',
        message: '出现虚伪夸夸套话，必须采用平实真诚方式承接',
        matchedSnippet: match.group(0),
      ));
    }

    return violations;
  }

  /// 3. 检测违背苏格拉底原则的剧透括号与括号式元解释
  static List<PromptEvalViolation> checkSpoilerParentheses(
    String concept,
    String text,
  ) {
    final violations = <PromptEvalViolation>[];

    // 匹配全角括号（...）与半角括号 (...)
    final bracketRegex = RegExp(r'[（\(]([^）\)]+)[）\)]');
    final matches = bracketRegex.allMatches(text);

    final spoilerPattern = RegExp(
      r'(?:其实就是|这其实是|这就是所谓的|因为.*所以|原因是|导致.*这就是|总需求反弹了|答案是|原理(?:就是|是)|剧透|正确原因|错误原因|也就是说)',
    );

    for (final m in matches) {
      final inner = m.group(1)?.trim() ?? '';
      
      // 条件 A: 括号内包含自我揭晓或剧透关键词
      if (spoilerPattern.hasMatch(inner)) {
        violations.add(PromptEvalViolation(
          category: PromptViolationCategory.spoilerParentheses,
          ruleName: 'spoiler_bracket_content',
          message: '括号内包含剧透或元解释内容，破坏苏格拉底引而不发的探索感',
          matchedSnippet: m.group(0),
        ));
      }
      // 条件 B: 括号内直接包含了当前概念名称（例如在杰文斯悖论中输出“这就是杰文斯悖论”）
      else if (concept.isNotEmpty && inner.contains(concept)) {
        violations.add(PromptEvalViolation(
          category: PromptViolationCategory.spoilerParentheses,
          ruleName: 'self_naming_spoiler_bracket',
          message: '括号内直接点破了当前概念名“$concept”，提前泄露核心底牌',
          matchedSnippet: m.group(0),
        ));
      }
      // 条件 C: 尾部带有超长（>25字）自言自语式的解释括号
      else if (inner.length > 25 && m.end >= text.trim().length - 2) {
        violations.add(PromptEvalViolation(
          category: PromptViolationCategory.spoilerParentheses,
          ruleName: 'trailing_explanation_bracket',
          message: '末尾带有过长的括号式解释，属于典型的 AI 提示词污染外泄',
          matchedSnippet: m.group(0),
        ));
      }
    }

    return violations;
  }

  /// 4. 检测死板实物强行类比（硬塞不相关的物理实体）
  static List<PromptEvalViolation> checkRigidEntityAnalogy(
    String concept,
    String text,
  ) {
    final violations = <PromptEvalViolation>[];

    // 针对「第一性原理」：本质是追溯物理本质/最小事实，不可生硬强塞“快递盒/快递箱/收纳盒/水龙头/借条”
    if (concept.contains('第一性原理')) {
      final mismatchRegex = RegExp(
        r'(?:快递盒|快递箱|装满乱七八糟旧东西的箱子|把箱子倒空|水龙头|借条)',
      );
      final m = mismatchRegex.firstMatch(text);
      if (m != null) {
        violations.add(PromptEvalViolation(
          category: PromptViolationCategory.rigidEntityAnalogy,
          ruleName: 'first_principles_mismatched_entity',
          message: '第一性原理应当拆解到底层基础事实/物理原材料，强行套用“${m.group(0)}”属于生硬死板的生搬硬套',
          matchedSnippet: m.group(0),
        ));
      }
    }

    // 针对「杰文斯悖论」：本质是效率提升引发总需求反弹，不可生硬强塞“快递盒/水龙头/收纳盒/借条”
    if (concept.contains('杰文斯悖论')) {
      final mismatchRegex = RegExp(r'(?:快递盒|快递箱|收纳盒|水龙头|借条)');
      final m = mismatchRegex.firstMatch(text);
      if (m != null) {
        violations.add(PromptEvalViolation(
          category: PromptViolationCategory.rigidEntityAnalogy,
          ruleName: 'jevons_paradox_mismatched_entity',
          message: '杰文斯悖论属于资源利用效率与反弹效应，强行套用“${m.group(0)}”属于不当物理实体',
          matchedSnippet: m.group(0),
        ));
      }
    }

    // 针对「闭包」：不可生硬套用“水龙头/柜台排队/借条/快递盒”
    if (concept.contains('闭包')) {
      final mismatchRegex = RegExp(r'(?:水龙头|柜台排队|借条|快递盒)');
      final m = mismatchRegex.firstMatch(text);
      if (m != null) {
        violations.add(PromptEvalViolation(
          category: PromptViolationCategory.rigidEntityAnalogy,
          ruleName: 'closure_mismatched_entity',
          message: '闭包应以作用域/背包/私有房间等作为类比，不应强套“${m.group(0)}”',
          matchedSnippet: m.group(0),
        ));
      }
    }

    // 针对「递归」：不可生硬套用“水龙头/借条/快递盒”
    if (concept.contains('递归')) {
      final mismatchRegex = RegExp(r'(?:水龙头|借条|快递盒)');
      final m = mismatchRegex.firstMatch(text);
      if (m != null) {
        violations.add(PromptEvalViolation(
          category: PromptViolationCategory.rigidEntityAnalogy,
          ruleName: 'recursion_mismatched_entity',
          message: '递归适合用排队问前排、套娃、镜子类比，不应强套“${m.group(0)}”',
          matchedSnippet: m.group(0),
        ));
      }
    }

    // 检测是否机械复读了 3d6f0e8 提示词中的死板实体列表
    final rigidEnumRegex = RegExp(
      r'水龙头.*快递盒.*柜台排队|快递盒.*排队.*水龙头',
    );
    final rigidMatch = rigidEnumRegex.firstMatch(text);
    if (rigidMatch != null) {
      violations.add(PromptEvalViolation(
        category: PromptViolationCategory.rigidEntityAnalogy,
        ruleName: 'rigid_entity_enum_leakage',
        message: '机械复现了提示词中被废弃的死板实体列表',
        matchedSnippet: rigidMatch.group(0),
      ));
    }

    return violations;
  }

  /// 5. 检测首轮提前掀底牌 / 教科书式定义倾倒
  static List<PromptEvalViolation> checkPrematureAnswerDump(
    String concept,
    String text, {
    int turn = 1,
  }) {
    final violations = <PromptEvalViolation>[];

    // 仅在首轮严格防掀底牌
    if (turn == 1) {
      if (concept.contains('第一性原理')) {
        final dumpRegex = RegExp(
          r'第一性原理(?:\s*[（\(][a-zA-Z\s]+[）\)])?\s*(?:其实)?(?:是|指|就是).*(?:由?亚里士多德|从头算|回到事物最基本的|物理学角度|从物理角度推导)',
        );
        final m = dumpRegex.firstMatch(text);
        if (m != null) {
          violations.add(PromptEvalViolation(
            category: PromptViolationCategory.prematureAnswerDump,
            ruleName: 'premature_answer_first_principles',
            message: '首轮直接抛出第一性原理的学术定义，违背苏格拉底引而不发原则',
            matchedSnippet: m.group(0),
          ));
        }
      }

      if (concept.contains('杰文斯悖论')) {
        final dumpRegex = RegExp(
          r'杰文斯悖论(?:\s*[（\(][a-zA-Z\s]+[）\)])?\s*(?:其实)?(?:是|指|就是|的核心).*(?:技术进步|提高利用效率|总消耗反而增加|能源需求反弹|威廉·斯坦利)',
        );
        final m = dumpRegex.firstMatch(text);
        if (m != null) {
          violations.add(PromptEvalViolation(
            category: PromptViolationCategory.prematureAnswerDump,
            ruleName: 'premature_answer_jevons_paradox',
            message: '首轮直接揭晓杰文斯悖论的结论机制，剥夺了用户的推导乐趣',
            matchedSnippet: m.group(0),
          ));
        }
      }

      if (concept.contains('闭包')) {
        final dumpRegex = RegExp(
          r'闭包(?:\s*[（\(][a-zA-Z\s]+[）\)])?\s*(?:其实)?(?:是|指|就是).*(?:有权访问|词法作用域|自由变量|内部函数访问外部变量)',
        );
        final m = dumpRegex.firstMatch(text);
        if (m != null) {
          violations.add(PromptEvalViolation(
            category: PromptViolationCategory.prematureAnswerDump,
            ruleName: 'premature_answer_closure',
            message: '首轮直接灌输闭包的教科书定义，缺少直觉搭梯子步骤',
            matchedSnippet: m.group(0),
          ));
        }
      }

      if (concept.contains('递归')) {
        final dumpRegex = RegExp(
          r'递归(?:\s*[（\(][a-zA-Z\s]+[）\)])?\s*(?:其实)?(?:是|指|就是).*(?:函数.*调用自[身己]|基线条件)',
        );
        final m = dumpRegex.firstMatch(text);
        if (m != null) {
          violations.add(PromptEvalViolation(
            category: PromptViolationCategory.prematureAnswerDump,
            ruleName: 'premature_answer_recursion',
            message: '首轮直接灌输递归定义，没有拆解为直觉小步',
            matchedSnippet: m.group(0),
          ));
        }
      }
    }

    return violations;
  }

  /// 6. 检测苏格拉底聚焦反诘与脚手架提问
  static List<PromptEvalViolation> checkQuestionScaffold(String text) {
    final violations = <PromptEvalViolation>[];

    final questionMatches = RegExp(r'[？?]').allMatches(text).toList();

    // 缺少反诘提问
    if (questionMatches.isEmpty) {
      violations.add(const PromptEvalViolation(
        category: PromptViolationCategory.missingQuestion,
        ruleName: 'missing_socratic_question',
        message: '回复中未包含任何启发式反问，沦为单向说教',
      ));
    }
    // 反诘过多（超过2个），审讯式轰炸
    else if (questionMatches.length > 2) {
      violations.add(PromptEvalViolation(
        category: PromptViolationCategory.interrogationOverload,
        ruleName: 'interrogation_overload',
        message: '单轮提问过多（包含 ${questionMatches.length} 个问号），违背“每次只抛 1 个小问题”的脚手架原则',
        matchedSnippet: '包含 ${questionMatches.length} 个问号',
      ));
    }

    // 检查结尾是否以反诘自然收束
    final trimmed = text.trim();
    final endsWithQuestion = trimmed.endsWith('？') ||
        trimmed.endsWith('?') ||
        trimmed.endsWith('？”') ||
        trimmed.endsWith('?"') ||
        trimmed.endsWith("?'") ||
        trimmed.endsWith("？'");

    if (!endsWithQuestion && questionMatches.isNotEmpty) {
      violations.add(const PromptEvalViolation(
        category: PromptViolationCategory.missingQuestion,
        ruleName: 'question_not_at_end',
        message: '末尾启发问题未自然承接在最后一句，存在把提问埋在中间的假启发风险',
      ));
    }

    return violations;
  }

  /// 7. 检测排版与字数篇幅（语音朗读友好）
  static List<PromptEvalViolation> checkFormattingAndLength(String text) {
    final violations = <PromptEvalViolation>[];

    final len = text.trim().length;
    if (len < 40) {
      violations.add(PromptEvalViolation(
        category: PromptViolationCategory.lengthOutOfRange,
        ruleName: 'response_too_short',
        message: '回复过于简略（仅 $len 字），未充分展开生活场景直觉',
      ));
    } else if (len > 380) {
      violations.add(PromptEvalViolation(
        category: PromptViolationCategory.lengthOutOfRange,
        ruleName: 'response_too_long',
        message: '回复过长（$len 字，推荐 80-200 字），语音播报容易听感疲劳',
      ));
    }

    // 检测机械八股标题或虚假标签
    final badgeRegex = RegExp(
      r'【(?:核心原理|底层逻辑|底层现实|反诘追问|机制拆解|总结)】|🎯|⚙️|⚡',
    );
    final badgeMatch = badgeRegex.firstMatch(text);
    if (badgeMatch != null) {
      violations.add(PromptEvalViolation(
        category: PromptViolationCategory.roboticFormatting,
        ruleName: 'robotic_block_headers',
        message: '包含了机械模板标题或假标签，破坏自然对话质感',
        matchedSnippet: badgeMatch.group(0),
      ));
    }

    // 检查加粗标记是否过度使用
    final boldCount = RegExp(r'\*\*').allMatches(text).length;
    if (boldCount > 6) {
      violations.add(PromptEvalViolation(
        category: PromptViolationCategory.roboticFormatting,
        ruleName: 'excessive_markdown_bold',
        message: '加粗标记使用过多（${boldCount ~/ 2} 处），语音转播报不需要视觉过度强调',
      ));
    }

    return violations;
  }
}

/// 违规类别枚举
enum PromptViolationCategory {
  forbiddenMannerism, // 违禁口癖 / 轻浮套话（如“咱”、“先不管这个词听着多高级”）
  flatteryCliche, // 虚伪夸夸腔（如“问得好！”、“完全正确！”）
  spoilerParentheses, // 括号剧透 / 括号内元解释
  rigidEntityAnalogy, // 死板实物强行类比（脱离场景硬塞快递盒、水龙头等）
  prematureAnswerDump, // 首轮直接掀底牌 / 教科书式定义倾倒
  interrogationOverload, // 连珠炮式提问（一轮出现多个问号轰炸）
  missingQuestion, // 缺少启发式反问 / 变成单向讲解
  roboticFormatting, // 机械模板标题或假标签（如【核心原理】、🎯等）
  lengthOutOfRange, // 篇幅失控（过短或过长，不符合语音朗读友好要求）
}

/// 违规条目实体
class PromptEvalViolation {
  final PromptViolationCategory category;
  final String ruleName;
  final String message;
  final String? matchedSnippet;

  const PromptEvalViolation({
    required this.category,
    required this.ruleName,
    required this.message,
    this.matchedSnippet,
  });

  @override
  String toString() => '[$ruleName] $message (${matchedSnippet ?? ""})';
}

/// 评估结果
class PromptEvalResult {
  final String concept;
  final String response;
  final List<PromptEvalViolation> violations;

  const PromptEvalResult({
    required this.concept,
    required this.response,
    required this.violations,
  });

  bool get passed => violations.isEmpty;
  bool get hasViolations => violations.isNotEmpty;

  bool hasViolation(PromptViolationCategory category) =>
      violations.any((v) => v.category == category);

  List<PromptEvalViolation> getViolations(PromptViolationCategory category) =>
      violations.where((v) => v.category == category).toList();

  String summary() {
    if (passed) return 'PASS: All quality checks passed for "$concept"';
    final sb = StringBuffer(
      'FAIL: ${violations.length} violations for "$concept":\n',
    );
    for (final v in violations) {
      sb.writeln(
        '  - [${v.category.name}] ${v.ruleName}: ${v.message} (matched: "${v.matchedSnippet}")',
      );
    }
    return sb.toString();
  }
}

/// 系统提示词静态规范检验器
class PromptSystemRuleValidator {
  PromptSystemRuleValidator._();

  /// 验证系统提示词的核心骨架与去 AI 味规范
  static List<String> validateSystemPrompt(String systemPrompt) {
    final issues = <String>[];

    // 1. 核心角色与苏格拉底宗旨
    if (!systemPrompt.contains('回响')) {
      issues.add('缺少「回响」角色定位');
    }
    if (!systemPrompt.contains('苏格拉底')) {
      issues.add('缺少「苏格拉底」教学法定义');
    }
    if (!systemPrompt.contains('大白话')) {
      issues.add('缺少「大白话」讲透复杂知识的基调说明');
    }

    // 2. 四大教学原则完整性
    final requiredPrinciples = [
      '轻量摸底',
      '锚定已知',
      '生活类比',
      '脚手架式引导',
      '费曼复述',
    ];
    for (final p in requiredPrinciples) {
      if (!systemPrompt.contains(p)) {
        issues.add('四大教学原则中缺少关键词: "$p"');
      }
    }

    // 3. 去 AI 味规范完整性
    final antiAiSpecs = [
      '语音朗读友好',
      '去 AI 味',
      '严禁虚伪夸夸腔',
      '严禁公文与列表腔',
      '篇幅精炼',
      '代码与公式克制',
      '仅抛出 1 个',
    ];
    for (final spec in antiAiSpecs) {
      if (!systemPrompt.contains(spec)) {
        issues.add('去 AI 味铁律中缺少约束: "$spec"');
      }
    }

    // 4. 防回归负向约束（避免 3d6f0e8 的坏模式重新渗入）
    if (systemPrompt.contains('必须且只能包含生活物理实体')) {
      issues.add('包含强制实物限制（“必须且只能包含生活物理实体”），会导致概念削足适履');
    }
    if (systemPrompt.contains('水龙头、快递盒、柜台排队、借条、钥匙、收纳盒')) {
      issues.add('包含硬编码的生硬实体枚举列表，易导致 AI 机械套用');
    }
    if (systemPrompt.contains('咱先不管') || systemPrompt.contains('咱拿')) {
      issues.add('提示词范例中包含违禁口癖“咱”，会污染模型输出');
    }
    if (systemPrompt.contains('（正确原因：') || systemPrompt.contains('（错误原因：')) {
      issues.add('范例中包含带括号的解题/元解释，会导致模型在输出时模仿带括号剧透');
    }

    return issues;
  }
}
