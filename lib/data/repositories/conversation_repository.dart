import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../domain/models/knowledge_models.dart';
import '../app_paths.dart';
import '../storage/file_store.dart';

/// 单一长期学习会话的本地工作记忆仓库（落盘至 `conversation.json`）
class ConversationRepository {
  final FileStore _store;
  final Uuid _uuid;

  ConversationRepository(this._store, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  String nextMessageId() => _uuid.v4();

  Future<ConversationMemory> load() async {
    try {
      final raw = await _store.readOrNull(AppPaths.conversationFile);
      if (raw == null || raw.trim().isEmpty) {
        return ConversationMemory.empty();
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return ConversationMemory.empty();
      return ConversationMemory.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return ConversationMemory.empty();
    }
  }

  Future<void> save(ConversationMemory memory) async {
    try {
      await _store.write(
        AppPaths.conversationFile,
        const JsonEncoder.withIndent('  ').convert(memory.toJson()),
      );
    } catch (_) {}
  }
}
