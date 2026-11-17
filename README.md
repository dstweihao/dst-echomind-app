# 回响 (EchoMind)

<p align="center">
  <img src="assets/icon/icon.png" width="96" height="96" alt="回响 Logo" />
</p>

<p align="center">
  一个基于 DeepSeek 对话与语音能力的跨平台学习应用。<br />
  用苏格拉底反问带你一步步想明白问题，并将学通的内容持续沉淀为本地 Markdown 笔记。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows-2563EB" alt="Platforms" />
  <img src="https://img.shields.io/badge/Flutter-3.47%2B-02569B" alt="Flutter" />
  <img src="https://img.shields.io/badge/Model-DeepSeek-4D6BFE" alt="DeepSeek" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-34C759" alt="MIT License" /></a>
</p>

## 为什么做这个

直接向大模型提问，往往只拿到一段现成答案，看过就忘。回响想解决两件事：

- **只给启发，不直接喂答案**：遇到不懂的概念，先用大白话和类比建立直觉，每次只抛一个小问题引导你自己推导，直到能用自己的话讲清楚。
- **单一长期对话，不堆垃圾窗口**：没有繁琐的多会话列表。所有学习都在同一条对话流里持续推进，聊透的知识点会自动提炼成高密度的本地 Markdown 文档，旧对话达到上下文上限后自动压缩，学习脉络不断档。

## 主要功能

### 苏格拉底式引导学习
- 先快速判断你的理解盲区，不发冗长问卷。
- 优先用生活类比和已有笔记打通直觉，再落到专业术语。
- 每次只围绕一个点追问；卡壳时换角度给台阶，最后用一句话复述收尾巩固。

### 语音提问与流式朗读
- **双模式输入**：输入框支持打字与语音随时切换；语音模式下按住说话、松手发送、上滑取消，录音打包为 16kHz WAV，经 DeepSeek ASR（`/v1/tools/asr`）转文字。
- **边生成边播报**：模型流式输出的同时，通过 DeepSeek WebSocket TTS（`wss://api.deepseek.com/v1/tools/tts`）接收 24kHz 原始 PCM 音频流，由 `flutter_soloud` 连续播放，无分段停顿；支持随时打断、静音、点击任意回复气泡重播，内置 `stella`（海星）与 `tide`（暗潮）两种音色试听切换。

### 自动知识沉淀与上下文压缩
- **自动为主、手动为辅**：每新增 3 轮问答在后台静默提炼一次，达到上限（默认 20 条消息或 12,000 字）自动压缩旧对话并保留近期原话；顶栏也可随时手动触发。纯闲聊不会写入知识库。
- **高信息密度笔记**：提炼遵循精炼原则，每条知识点仅记录 `核心 / 类比 / 误区 / 复述`，增量追加、默认不可删除。
- **两层纯文本结构**：
  - `KNOWLEDGE.md`：总知识索引，每次对话自动注入上下文，让模型知道你已经掌握了什么。
  - `docs/<category>.md`：按学科或专题归类的详情文档，可在左侧抽屉随时翻阅，也可以直接带入当前对话继续复习。

### 模型与设置
- 默认使用 `deepseek-flash`（默认关闭深度思考以保证语音首字响应速度，可按需开启），支持切换 `deepseek-v4-pro`。
- 设置页只保留 DeepSeek API Key、账户实时余额查询、模型与语音配置、版本检查更新。

## 本地数据结构

所有对话与笔记均为本地纯文本文件，可直接配合同步盘或 Git 备份：

```text
<数据目录>/
├── conversation.json     # 当前单一会话与滚动摘要
├── KNOWLEDGE.md          # 总知识索引（自动注入对话上下文）
└── docs/
    ├── economics.md      # 按专题增量追加的知识笔记
    ├── programming.md
    └── ...
```

## 技术栈

- **框架**：Flutter（Android / iOS / macOS / Windows）、Riverpod、GoRouter
- **大模型与语音接口**：DeepSeek Chat（`deepseek-flash` / `deepseek-v4-pro`）、DeepSeek ASR、DeepSeek WebSocket / HTTP TTS
- **音频链路**：`record`（16kHz PCM 录音与 WAV 封包）+ `flutter_soloud`（24kHz PCM 连续流式播放）

## 本地运行与测试

```bash
git clone https://github.com/dstweihao/dst-echomind-app.git
cd dst-echomind-app

flutter pub get
dart analyze
flutter test

# 按需指定目标平台运行（macos / windows / android / ios）
flutter run -d macos
```

启动后点击右上角设置图标，填入自己的 DeepSeek API Key 即可使用。

## 许可证

本项目基于 [MIT License](LICENSE) 开源。

## 作者

- GitHub: [github.com/dstweihao](https://github.com/dstweihao)
- 个人网站: [https://dstweihao.cn](https://dstweihao.cn)
- 微信公众号: `码上生长`
