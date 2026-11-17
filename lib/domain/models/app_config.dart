import 'ai_settings.dart';

/// 全局配置 — 对应 `/EchoMind/config.yaml`
///
/// 不含任何密钥（密钥单独存储在设备本地安全存储中）。
class AppConfig {
  final int schemaVersion;
  final AiSettings ai;

  const AppConfig({
    this.schemaVersion = currentSchemaVersion,
    this.ai = const AiSettings(),
  });

  static const int currentSchemaVersion = 1;

  static const AppConfig defaults = AppConfig();

  AppConfig copyWith({
    int? schemaVersion,
    AiSettings? ai,
  }) {
    return AppConfig(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      ai: ai ?? this.ai,
    );
  }

  factory AppConfig.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return defaults;
    final rawAi = map['ai'];
    return AppConfig(
      schemaVersion: _toInt(map['schema_version'], currentSchemaVersion),
      ai: AiSettings.fromMap(rawAi is Map ? rawAi : null),
    );
  }

  Map<String, dynamic> toMap() => {
        'schema_version': schemaVersion,
        'ai': ai.toMap(),
      };

  static int _toInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfig &&
          other.schemaVersion == schemaVersion &&
          other.ai == ai;

  @override
  int get hashCode => Object.hash(schemaVersion, ai);
}
