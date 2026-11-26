import 'dart:convert';

import '../../domain/models/knowledge_models.dart';
import '../app_paths.dart';
import '../storage/file_store.dart';

/// 各学科自适应能力画像与动态路线图本地持久化仓库（`EchoMind/mastery/<slug>.json`）
class MasteryRepository {
  final FileStore _store;

  MasteryRepository(this._store);

  Future<MasteryProfile?> loadProfile(String slug) async {
    final safeSlug = KnowledgeEntry.normalizeSlug(slug);
    try {
      final raw =
          await _store.readOrNull(AppPaths.masteryProfileFile(safeSlug));
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return MasteryProfile.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfile(MasteryProfile profile) async {
    await _store.ensureDirectory(AppPaths.masteryDir);
    final safeSlug = KnowledgeEntry.normalizeSlug(profile.slug);
    final normalized = profile.copyWith(slug: safeSlug);
    await _store.write(
      AppPaths.masteryProfileFile(safeSlug),
      const JsonEncoder.withIndent('  ').convert(normalized.toJson()),
    );
  }

  Future<void> deleteProfile(String slug) async {
    final safeSlug = KnowledgeEntry.normalizeSlug(slug);
    final path = AppPaths.masteryProfileFile(safeSlug);
    if (await _store.exists(path)) {
      await _store.delete(path);
    }
  }

  Future<Map<String, MasteryProfile>> loadAllProfiles() async {
    try {
      if (!await _store.exists(AppPaths.masteryDir)) return const {};
      final entries = await _store.list(AppPaths.masteryDir);
      final map = <String, MasteryProfile>{};
      for (final entry in entries) {
        if (entry.isDirectory || !entry.name.toLowerCase().endsWith('.json')) {
          continue;
        }
        final raw = await _store.readOrNull(entry.path);
        if (raw == null || raw.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final profile =
                MasteryProfile.fromJson(decoded.cast<String, dynamic>());
            if (profile.slug.isNotEmpty) {
              map[profile.slug] = profile;
            }
          }
        } catch (_) {
          continue;
        }
      }
      return map;
    } catch (_) {
      return const {};
    }
  }
}
