# 回响 (EchoMind)

<p align="center">
  <img src="assets/icon/icon.png" width="96" height="96" alt="回响" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows-2563EB" alt="Platforms" />
  <img src="https://img.shields.io/badge/Flutter-3.47%2B-02569B" alt="Flutter" />
  <img src="https://img.shields.io/badge/Model-DeepSeek-4D6BFE" alt="DeepSeek" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-34C759" alt="MIT License" /></a>
</p>

平时直接问 AI，它一上来就把完整答案甩给你，自己根本没动脑，看的时候觉得懂了，转头还是不会，其实没学进去多少。

回响用**苏格拉底反诘法**来学东西：不直接给现成答案，而是用通俗易懂的大白话，举生活中日常见到的例子把原理拆开，每次只追问一个小问题，带着你自己一步步想明白，直到能用自己的话讲清楚。

应用基于 DeepSeek 的对话和语音接口开发，支持 Android / iOS / macOS / Windows，全程只留一条长期对话；聊透的知识点会自动记到本地 Markdown 里，方便以后翻看和复习。

## 功能

- **苏格拉底式对话**：先看你卡在哪，再用日常例子把原理讲清楚，每次只问一个点，卡壳时给提示，搞懂后让你用一句话复述一遍。
- **语音输入**：输入框可以切打字或语音。语音下按住说话、松手发送、上滑取消，录音转成 16kHz WAV 走 DeepSeek ASR（`/v1/tools/asr`）。
- **流式播报**：文字边生成边通过 DeepSeek WebSocket TTS（`wss://api.deepseek.com/v1/tools/tts`）拉取 24kHz PCM，用 `flutter_soloud` 连续播放。支持随时打断、静音、点任意消息重播，内置 `stella`（海星）和 `tide`（暗潮）两个音色。
- **单会话与自动笔记**：不建一堆杂乱窗口。每多聊 3 轮，后台静默把讲透的知识点提炼进本地笔记，纯闲聊不记；对话超过 20 条或 12,000 字时自动压缩旧消息，保留最近几轮原话，也可以手动点压缩。笔记只记录 `核心 / 类比 / 误区 / 复述`，默认不能删除。
- **模型配置**：默认 `deepseek-flash`（默认关深度思考，回复快，可自己打开），也可以切 `deepseek-v4-pro`。设置页支持填 API Key、查账户余额、试听音色和检查更新。

## 本地文件结构

所有记录都是纯文本，放在本地文档目录的 `EchoMind` 下，自己配同步盘或 Git 备份就行：

```text
EchoMind/
├── config.yaml           # 模型与语音设置（不含 API Key）
├── conversation.json     # 当前对话与历史摘要
├── KNOWLEDGE.md          # 总知识清单（每次对话自动带给模型）
└── docs/
    ├── economics.md      # 按专题追加的笔记详情，左侧抽屉可翻阅或带入复习
    ├── programming.md
    └── ...
```

## 技术栈

- Flutter（Android / iOS / macOS / Windows）、Riverpod、GoRouter
- DeepSeek Chat（`deepseek-flash` / `deepseek-v4-pro`）、DeepSeek ASR、DeepSeek TTS
- `record`（16kHz 录音与 WAV 打包）+ `flutter_soloud`（24kHz PCM 流式播放）

## 运行与测试

```bash
git clone https://github.com/dstweihao/dst-echomind-app.git
cd dst-echomind-app

flutter pub get
dart analyze
flutter test

# 目标平台：macos / windows / android / ios
flutter run -d macos
```

打开后点右上角设置，填入自己的 DeepSeek API Key 即可。

## 许可证

[MIT License](LICENSE)

## 作者

- GitHub: [github.com/dstweihao](https://github.com/dstweihao)
- 网站: [https://dstweihao.cn](https://dstweihao.cn)
- 微信公众号: `码上生长`
