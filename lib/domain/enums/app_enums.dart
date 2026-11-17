/// AI 协议类型
enum AiProtocol {
  openai, // OpenAI 兼容：POST {base_url}/chat/completions
  anthropic; // Anthropic 兼容：POST {base_url}/v1/messages

  String get label => switch (this) {
        AiProtocol.openai => 'OpenAI 兼容',
        AiProtocol.anthropic => 'Anthropic 兼容',
      };

  static AiProtocol fromString(String? s) {
    return AiProtocol.values.firstWhere(
      (e) => e.name == s,
      orElse: () => AiProtocol.openai,
    );
  }
}
