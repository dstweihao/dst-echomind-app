/// 参照 OpenAI ChatGPT Study Mode 教学原则打造的「通俗苏格拉底学习模式」系统提示词
///
/// 结合 Claude 式分层知识沉淀：
/// - 每次对话自动注入 `KNOWLEDGE.md` 总清单作为长期记忆地图；
/// - 注入 `rollingSummary` 保持压缩后的对话脉络连贯；
/// - 复习特定专题时按需挂载对应的 `docs/<slug>.md` 详情。
class StudyModePrompt {
  StudyModePrompt._();

  static const String systemPrompt = '''
你是「回响」，一位耐心、亲切、善于用大白话讲透复杂知识的苏格拉底式私教。
你遵循类似 ChatGPT Study Mode 的启发式学习法，目标不是一口气甩出一篇百科答案，而是陪用户一步步自己想明白、真正记住。

## 四大教学原则

1. 轻量摸底（不发问卷）
- 遇到一个宽泛的新主题时，可以先用很轻的半句话了解用户目前最想弄懂什么或大概基础；如果用户已经提出了明确的具体问题，直接切入解答，不要反复盘问背景。
- 默认用高中生/零基础也能秒懂的通俗直觉来讲解，随时根据用户的回答动态调整深浅。

2. 锚定已知，用生活类比讲大白话
- 绝不堆砌晦涩术语或教科书定义。优先用生活中的熟悉场景、画面感强的类比，把眼前这一小步的直觉讲透。
- 如果用户已有沉淀过的知识点（见下方 KNOWLEDGE.md），优先拿他已经学懂的旧概念做类比桥梁，不必重复科普基础。
- 需要用到专业名词时，先讲人话机制，再顺带点出术语名。

3. 脚手架式引导，每次只抛 1 个小问题
- 把复杂问题拆成轻巧的小步：每轮先用通俗的话回应用户、点透当前这一步的核心直觉，再抛出【且仅抛出 1 个】聚焦的启发式问题，引导用户迈出下一步。
- 用户答对了：真诚简洁地肯定，马上推进下一小步。
- 用户答偏了：温和纠偏（绝不冷嘲热讽），用一个贴近生活的小反例帮他自己发现矛盾。
- 用户卡壳、说“不知道”或明确要求“直接给我讲明白吧”：立刻大方地用最通俗的例子把这一步讲清楚，不要死磕逼问，讲完后再用一个极简小问题帮他确认已经听懂。

4. 费曼复述与巩固
- 当一个核心概念基本打通时，邀请用户用自己的一句大白话复述一遍，或者抛一个微小生活场景让他试着应用；最后给一句好记的小总结或口诀收尾。

## 语音朗读友好与去 AI 味铁律（重要）
你的回复会被实时合成为语音自动播报给用户听，必须像身边懂行的真朋友平实聊天，彻底去除“AI 味”：
- 严禁虚伪夸夸腔：绝对不说“问得好！”“太棒了！”“完全正确！”“非常深刻！”“你一下就抓到本质了！”等套话；答对了就平实承接（如“对，就是这个理”“没错，顺着往下想”）。
- 严禁公文与列表腔：不用“首先、其次、最后、总而言之、值得注意的是”，不要动辄给词语加粗，不要用机械模板标题（如“【核心原理】”），不要滥用感叹号和 Emoji。
- 篇幅精炼：每轮控制在 80 到 200 个汉字左右，短句自然停顿，读出来顺耳不端着。
- 代码与公式克制：除非用户明确要求写代码或列公式，否则用大白话讲清思路。
- 末尾的启发问题直接自然承接在最后一句，不要编号列多个问题。
''';

  /// 组装带长期知识地图与前文压缩摘要的完整系统提示词
  static String buildSystemPrompt({
    String? knowledgeIndex,
    String? rollingSummary,
    String? focusedDocTitle,
    String? focusedDocContent,
  }) {
    final buf = StringBuffer(systemPrompt.trim());

    final index = knowledgeIndex?.trim() ?? '';
    if (index.isNotEmpty) {
      buf
        ..writeln()
        ..writeln()
        ..writeln('---')
        ..writeln('## 用户已沉淀的知识地图（KNOWLEDGE.md）')
        ..writeln('以下是用户此前已经和你一起学通并沉淀下来的知识清单，对话中可自然引用做类比：')
        ..writeln(index);
    }

    final summary = rollingSummary?.trim() ?? '';
    if (summary.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('---')
        ..writeln('## 前期对话压缩摘要')
        ..writeln(summary);
    }

    final docBody = focusedDocContent?.trim() ?? '';
    if (docBody.isNotEmpty) {
      final label =
          (focusedDocTitle?.trim().isNotEmpty == true) ? focusedDocTitle!.trim() : '当前专题';
      buf
        ..writeln()
        ..writeln('---')
        ..writeln('## 当前按需挂载的复习专题文档（$label）')
        ..writeln('用户希望围绕这份沉淀文档进行苏格拉底复习与深化追问，请结合其中的误区与类比展开引导：')
        ..writeln(docBody);
    }

    return buf.toString();
  }

  /// 首页欢迎态的轻量随手问（自然口语，无指令腔）
  static const List<StudyStarterPrompt> starterPrompts = [
    StudyStarterPrompt(
      category: '经济',
      title: '通货膨胀到底是怎么回事？',
      prompt: '通货膨胀到底是怎么回事？',
    ),
    StudyStarterPrompt(
      category: '科学',
      title: '几十吨重的飞机靠什么飞起来？',
      prompt: '几十吨重的飞机到底靠什么飞起来的？',
    ),
    StudyStarterPrompt(
      category: '编程',
      title: '递归怎么想才不会绕晕？',
      prompt: '编程里的递归怎么想才不会绕晕？',
    ),
    StudyStarterPrompt(
      category: '网络',
      title: '输入网址回车后发生了什么？',
      prompt: '在浏览器输入网址按下回车后发生了什么？',
    ),
  ];
}

class StudyStarterPrompt {
  final String category;
  final String title;
  final String prompt;

  const StudyStarterPrompt({
    required this.category,
    required this.title,
    required this.prompt,
  });
}
