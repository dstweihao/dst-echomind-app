# EchoMind (回响) - Claude Code 约束与协作规范

本项目为 **EchoMind (回响)**，一款基于 DeepSeek 对话与语音接口（ASR / TTS / Chat）的苏格拉底式学习应用。开发环境技术栈为 Flutter (Android / iOS / macOS / Windows)、Riverpod、GoRouter。

---

## 1. 核心边界与工程铁律 (Engineering Boundaries)

### 1.1 Git 边界
- **严禁擅自 Commit**：未经人类用户明确指令或确认，绝对禁止私自执行 `git commit`、`git push` 或创建 `git tag`。
- **严禁发散性重构**：严禁借“最佳实践”、“代码坏味道”、“统一代码风格”之名擅自修改与当前任务不相干的文件或模块。严格遵循“最小变更范围”原则。

### 1.2 磁盘优先与防覆盖编辑铁律 (Disk-First Rule)
- **强制读后写**：在修改任何已有文件前，**必须先调用工具从磁盘实时重新读取该文件最新内容**，严禁仅凭历史记忆或上下文旧内容直接覆盖，坚决杜绝冲刷覆盖用户手工做出的改动。
- **精准局部更新**：优先使用精准局部文本替换（Exact Match Replacement），避免无谓的全文件整体覆写。

---

## 2. 提示词工程刚性红线 (Prompt Hard Guardrails)

在编写、修改应用内任何 System Prompt、指导词或 Few-shot 范例时（如 `lib/data/ai/prompts/`），必须死守以下红线，严防模型产生刻板偏置与语境翻车：

1. **严禁强制枚举实物的死命令**：
   - 严禁向模型下达必须包含具体实物（如“水龙头”、“快递盒”、“柜台排队”等）的机械式死命令。
   - 启发机制应聚焦于“建立生活常识直觉”，而非强行绑定特定道具，避免在不相干学科场景中造成语境荒谬。

2. **严禁注入口癖与轻佻方言模板**：
   - 范例与引导词中严禁植入带有特定方言口癖或轻佻腔调的表达（如“咱”、“先不管这个词听着多高级”、“差的那 1 分钱跑哪儿去了”等）。
   - 防止大模型将范例中的特异性口癖泛化为全局刻板应答模板。

3. **保持克制平实的成年人对话基调**：
   - 语言基调必须自然平实、真诚克制，符合正常成年人的认知与教学交流。
   - **禁止自我加括号剧透**：严禁输出类似“（正确原因：...）”、“（内心潜台词：...）”等自言自语式剧透或旁白。
   - **禁止假大空鸡汤反问**：启发式反问必须聚焦于当前步的逻辑断层，严禁把反问异化为初中语文阅读理解式设问或空泛的心灵鸡汤。

4. **苏格拉底反诘真谛**：
   - 引而不发：复杂问题拆成轻巧小步，每轮仅抛出【1 个】聚焦的核心小反问，引导用户自己推理出答案。
   - 兜底大方：用户卡壳或明确要求直接讲时，干脆利落地用大白话讲透，绝不死磕逼问。

---

## 3. 常用开发与构建命令

```bash
# 依赖与分析
flutter pub get
dart analyze
flutter test

# 桌面端调试
flutter run -d macos

# macOS Detritus 清洗与签名（本地构建排错必备）
xattr -cr build/macos/Build/Products/Debug/echomind_app.app
codesign --force --deep --sign - build/macos/Build/Products/Debug/echomind_app.app
```

---

## 4. 架构与目录导引

- `lib/data/ai/prompts/`: 核心提示词定义（修改受上述提示词红线绝对约束）
- `lib/data/ai/`: DeepSeek 客户端（Chat、WebSocket TTS、ASR 协议实现）
- `lib/data/repositories/`: 知识库（KNOWLEDGE.md）、对话存储与配置持久化
- `lib/presentation/`: UI 视图与组件（极简、高效交互）
- `.agents/rules/`: 代理环境规则目录
