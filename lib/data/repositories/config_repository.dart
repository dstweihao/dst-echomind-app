import 'package:yaml/yaml.dart';

import '../../domain/models/ai_settings.dart';
import '../../domain/models/app_config.dart';
import '../app_paths.dart';
import '../serialization/frontmatter.dart';
import '../storage/file_store.dart';

/// 全局配置仓库，读写 `/EchoMind/config.yaml`（不含任何密钥）。
class ConfigRepository {
  final FileStore client;

  AppConfig? _cache;

  ConfigRepository(this.client);

  Future<AppConfig> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;

    final raw = await client.readOrNull(AppPaths.configFile);
    if (raw == null) {
      _cache = AppConfig.defaults;
      return _cache!;
    }

    try {
      final loaded = loadYaml(raw);
      if (loaded is! Map) {
        _cache = AppConfig.defaults;
        return _cache!;
      }
      _cache = AppConfig.fromMap(loaded);
      return _cache!;
    } catch (_) {
      _cache = AppConfig.defaults;
      return _cache!;
    }
  }

  Future<void> save(AppConfig config) async {
    await client.ensureDirectory(AppPaths.appRoot);
    await client.write(
      AppPaths.configFile,
      Frontmatter.dumpYaml(config.toMap()),
    );
    _cache = config;
  }

  Future<AppConfig> saveAiSettings(AiSettings ai) async {
    final current = await load();
    final next = current.copyWith(ai: ai);
    await save(next);
    return next;
  }

  void invalidate() => _cache = null;
}
