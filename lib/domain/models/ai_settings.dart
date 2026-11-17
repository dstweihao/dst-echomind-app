import '../enums/app_enums.dart';

/// AI 与语音接口配置
///
/// 存储在本地配置文件的 `ai:` 段，不含 API Key。
/// ⚠️ 安全边界：**API Key 不在此模型中**，密钥由 `SecretStore` 单独加密保存。
class AiSettings {
  /// 总开关。关闭后不发起远端 AI 请求
  final bool enabled;

  /// 协议类型，决定端点拼接方式
  final AiProtocol protocol;

  /// 服务地址，如 `https://api.deepseek.com`
  final String baseUrl;

  /// 模型名，默认使用 DeepSeek 最新官方快速模型 `deepseek-flash`
  final String model;

  final double temperature;
  final int maxTokens;

  /// 推理档位 low | high | max，为空则不传该参数
  final String? reasoningEffort;

  /// 是否开启深度思考模式（`deepseek-flash` 默认关闭以换取秒级语音首字响应）
  final bool enableThinking;

  final int timeoutSeconds;

  /// 人设预设标识
  final String persona;

  /// 是否像豆包一样自动流式朗读 AI 解答
  final bool autoPlayTts;

  /// DeepSeek TTS 音色：`stella`（海星女声）或 `tide`（暗潮男声）
  final String ttsVoiceId;

  /// DeepSeek ASR 语音转文字完成后是否自动发送提问
  final bool autoSendAfterAsr;

  const AiSettings({
    this.enabled = false,
    this.protocol = AiProtocol.openai,
    this.baseUrl = 'https://api.deepseek.com',
    this.model = 'deepseek-flash',
    this.temperature = 0.7,
    this.maxTokens = 4096,
    this.reasoningEffort = 'high',
    this.enableThinking = false,
    this.timeoutSeconds = 120,
    this.persona = 'study_mode_socratic',
    this.autoPlayTts = true,
    this.ttsVoiceId = 'stella',
    this.autoSendAfterAsr = true,
  });

  /// 默认值即 DeepSeek 最新公式推荐配置
  static const AiSettings defaults = AiSettings();

  /// 将已下线的旧模型名平滑迁移至官方最新模型名
  static String migrateModelName(String raw) {
    final trimmed = raw.trim();
    if (trimmed == 'deepseek-reasoner' || trimmed == 'deepseek-chat') {
      return 'deepseek-flash';
    }
    return trimmed;
  }

  AiSettings copyWith({
    bool? enabled,
    AiProtocol? protocol,
    String? baseUrl,
    String? model,
    double? temperature,
    int? maxTokens,
    String? reasoningEffort,
    bool clearReasoningEffort = false,
    bool? enableThinking,
    int? timeoutSeconds,
    String? persona,
    bool? autoPlayTts,
    String? ttsVoiceId,
    bool? autoSendAfterAsr,
  }) {
    return AiSettings(
      enabled: enabled ?? this.enabled,
      protocol: protocol ?? this.protocol,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      reasoningEffort: clearReasoningEffort
          ? null
          : (reasoningEffort ?? this.reasoningEffort),
      enableThinking: enableThinking ?? this.enableThinking,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      persona: persona ?? this.persona,
      autoPlayTts: autoPlayTts ?? this.autoPlayTts,
      ttsVoiceId: ttsVoiceId ?? this.ttsVoiceId,
      autoSendAfterAsr: autoSendAfterAsr ?? this.autoSendAfterAsr,
    );
  }

  // ---- 端点拼接 ----

  /// 规范化后的 base URL（去掉末尾斜杠）
  String get normalizedBaseUrl {
    var u = baseUrl.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// 是否指向 DeepSeek 官方端点
  bool get isDeepSeekEndpoint =>
      normalizedBaseUrl.toLowerCase().contains('deepseek.com');

  /// 补全后的对话请求端点
  String get chatEndpoint => switch (protocol) {
        AiProtocol.openai => '$normalizedBaseUrl/chat/completions',
        AiProtocol.anthropic => '$normalizedBaseUrl/v1/messages',
      };

  /// DeepSeek ASR 语音转文字端点
  String get asrEndpoint => '$normalizedBaseUrl/v1/tools/asr';

  /// DeepSeek TTS 整段合成 HTTP 端点
  String get ttsHttpEndpoint => '$normalizedBaseUrl/v1/tools/tts';

  /// DeepSeek TTS 流式合成 WebSocket 地址
  Uri ttsWebSocketUri({
    String? voiceId,
    String format = 'pcm',
    bool filterMarkdown = true,
  }) {
    final parsed = Uri.parse(normalizedBaseUrl);
    final wsScheme = parsed.scheme == 'http' ? 'ws' : 'wss';
    final basePath = parsed.path.endsWith('/')
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;
    return parsed.replace(
      scheme: wsScheme,
      path: '$basePath/v1/tools/tts',
      queryParameters: {
        'voice_id': (voiceId ?? ttsVoiceId).trim().isEmpty
            ? 'stella'
            : (voiceId ?? ttsVoiceId).trim(),
        'format': format,
        'filter_markdown': filterMarkdown.toString(),
      },
    );
  }

  /// 配置是否已达可用状态（不含 key，key 单独校验）
  bool get isConfigured =>
      enabled &&
      normalizedBaseUrl.isNotEmpty &&
      model.trim().isNotEmpty;

  /// 配置完整性检查，返回人类可读的问题列表
  List<String> validate() => [
        if (normalizedBaseUrl.isEmpty) '服务地址未填写',
        if (!normalizedBaseUrl.startsWith('http'))
          '服务地址必须以 http:// 或 https:// 开头',
        if (model.trim().isEmpty) '模型名称未填写',
        if (maxTokens <= 0) '最大输出 token 必须为正数',
        if (timeoutSeconds <= 0) '超时时间必须为正数',
      ];

  factory AiSettings.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return defaults;
    final rawModel = (map['model'] ?? defaults.model).toString();
    final migratedModel = migrateModelName(rawModel);
    return AiSettings(
      enabled: map['enabled'] == true || map['enabled'] == 'true',
      protocol: AiProtocol.fromString(map['protocol']?.toString()),
      baseUrl: (map['base_url'] ?? defaults.baseUrl).toString(),
      model: migratedModel.isEmpty ? defaults.model : migratedModel,
      temperature: _toDouble(map['temperature'], defaults.temperature),
      maxTokens: _toInt(map['max_tokens'], defaults.maxTokens),
      reasoningEffort: _nullableString(map['reasoning_effort']),
      enableThinking: _toBool(map['enable_thinking'], defaults.enableThinking),
      timeoutSeconds: _toInt(map['timeout_seconds'], defaults.timeoutSeconds),
      persona: (map['persona'] ?? defaults.persona).toString(),
      autoPlayTts: _toBool(map['auto_play_tts'], defaults.autoPlayTts),
      ttsVoiceId: _validVoice(map['tts_voice_id']?.toString()),
      autoSendAfterAsr:
          _toBool(map['auto_send_after_asr'], defaults.autoSendAfterAsr),
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'protocol': protocol.name,
        'base_url': normalizedBaseUrl,
        'model': model,
        'temperature': temperature,
        'max_tokens': maxTokens,
        if (reasoningEffort != null && reasoningEffort!.isNotEmpty)
          'reasoning_effort': reasoningEffort,
        'enable_thinking': enableThinking,
        'timeout_seconds': timeoutSeconds,
        'persona': persona,
        'auto_play_tts': autoPlayTts,
        'tts_voice_id': ttsVoiceId,
        'auto_send_after_asr': autoSendAfterAsr,
      };

  static bool _toBool(dynamic v, bool fallback) {
    if (v is bool) return v;
    if (v == 'true') return true;
    if (v == 'false') return false;
    return fallback;
  }

  static String _validVoice(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == 'stella' || v == 'tide') return v!;
    return defaults.ttsVoiceId;
  }

  static double _toDouble(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? fallback;
  }

  static int _toInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }

  static String? _nullableString(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiSettings &&
          other.enabled == enabled &&
          other.protocol == protocol &&
          other.baseUrl == baseUrl &&
          other.model == model &&
          other.temperature == temperature &&
          other.maxTokens == maxTokens &&
          other.reasoningEffort == reasoningEffort &&
          other.enableThinking == enableThinking &&
          other.timeoutSeconds == timeoutSeconds &&
          other.persona == persona &&
          other.autoPlayTts == autoPlayTts &&
          other.ttsVoiceId == ttsVoiceId &&
          other.autoSendAfterAsr == autoSendAfterAsr;

  @override
  int get hashCode => Object.hash(
        enabled,
        protocol,
        baseUrl,
        model,
        temperature,
        maxTokens,
        reasoningEffort,
        enableThinking,
        timeoutSeconds,
        persona,
        autoPlayTts,
        ttsVoiceId,
        autoSendAfterAsr,
      );

  @override
  String toString() =>
      'AiSettings(${protocol.name} · $model · thinking=$enableThinking · tts=$autoPlayTts/$ttsVoiceId)';
}
