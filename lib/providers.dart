import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'data/ai/ai_client.dart';
import 'data/ai/anthropic_client.dart';
import 'data/ai/context_compactor.dart';
import 'data/ai/deepseek_ocr_client.dart';
import 'data/ai/knowledge_organizer.dart';
import 'data/ai/mastery_calibrator.dart';
import 'data/ai/openai_client.dart';
import 'data/attachments/attachment_picker_service.dart';
import 'data/credentials/credentials_store.dart';
import 'data/repositories/config_repository.dart';
import 'data/repositories/conversation_repository.dart';
import 'data/repositories/knowledge_exporter.dart';
import 'data/repositories/knowledge_repository.dart';
import 'data/repositories/mastery_repository.dart';
import 'data/settings/app_settings_store.dart';
import 'data/storage/file_store.dart';
import 'data/storage/file_store_factory.dart';
import 'data/updates/update_client.dart';
import 'data/updates/update_config.dart';
import 'data/updates/update_installer.dart';
import 'data/voice/deepseek_asr_client.dart';
import 'data/voice/deepseek_tts_client.dart';
import 'data/voice/streaming_audio_player.dart';
import 'data/voice/voice_recorder_service.dart';
import 'domain/enums/app_enums.dart';
import 'domain/models/ai_settings.dart';
import 'domain/models/app_config.dart';
import 'domain/models/update_info.dart';
import 'domain/models/update_status.dart';

final initialStorageRootProvider = Provider<String>((ref) {
  throw StateError('initialStorageRootProvider 必须在 ProviderScope 中 override。');
});

final appSettingsStoreProvider = Provider<AppSettingsStore>((ref) {
  return AppSettingsStore();
});

final initialThemeModeProvider =
    Provider<ThemeMode>((ref) => ThemeMode.light);

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  Future<void> setMode(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await ref.read(appSettingsStoreProvider).saveThemeMode(mode);
  }
}

final storageRootProvider =
    NotifierProvider<StorageRootNotifier, String>(StorageRootNotifier.new);

class StorageRootNotifier extends Notifier<String> {
  @override
  String build() => ref.watch(initialStorageRootProvider);

  Future<void> changeTo(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed == state) return;

    await ref.read(appSettingsStoreProvider).saveStorageRoot(trimmed);
    state = trimmed;
  }

  Future<void> useDefault() async {
    await ref.read(appSettingsStoreProvider).clearStorageRoot();
  }
}

final fileStoreProvider = Provider<FileStore>((ref) {
  return createFileStore(ref.watch(storageRootProvider));
});

/// 设备本地加密存储，不随数据文件夹同步。
final secretStoreProvider = Provider<SecretStore>((ref) => SecretStore());

final aiApiKeyProvider = FutureProvider<String?>((ref) {
  return ref.watch(secretStoreProvider).loadAiApiKey();
});

final configRepositoryProvider = Provider<ConfigRepository>((ref) {
  return ConfigRepository(ref.watch(fileStoreProvider));
});

final appConfigProvider = FutureProvider<AppConfig>((ref) {
  return ref.watch(configRepositoryProvider).load();
});

final aiSettingsProvider = Provider<AiSettings>((ref) {
  return ref.watch(appConfigProvider).value?.ai ?? AiSettings.defaults;
});

final aiClientProvider = Provider<AiClient?>((ref) {
  final settings = ref.watch(aiSettingsProvider);
  if (!settings.isConfigured) return null;

  final apiKey = ref.watch(aiApiKeyProvider).value;
  if (apiKey == null || apiKey.trim().isEmpty) return null;

  final AiClient client = switch (settings.protocol) {
    AiProtocol.openai => OpenAiClient(settings: settings, apiKey: apiKey),
    AiProtocol.anthropic =>
      AnthropicClient(settings: settings, apiKey: apiKey),
  };

  ref.onDispose(client.dispose);
  return client;
});

final aiAvailableProvider = Provider<bool>((ref) {
  return ref.watch(aiClientProvider) != null;
});

final knowledgeRepositoryProvider = Provider<KnowledgeRepository>((ref) {
  return KnowledgeRepository(ref.watch(fileStoreProvider));
});

final knowledgeExporterProvider = Provider<KnowledgeExporter>((ref) {
  return const KnowledgeExporter();
});

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository(ref.watch(fileStoreProvider));
});

final contextCompactorProvider = Provider<ContextCompactor>((ref) {
  return ContextCompactor();
});

final knowledgeOrganizerProvider = Provider<KnowledgeOrganizer>((ref) {
  return const KnowledgeOrganizer();
});

final masteryRepositoryProvider = Provider<MasteryRepository>((ref) {
  return MasteryRepository(ref.watch(fileStoreProvider));
});

final masteryCalibratorProvider = Provider<MasteryCalibrator>((ref) {
  return const MasteryCalibrator();
});

final deepSeekAsrClientProvider = Provider<DeepSeekAsrClient?>((ref) {
  final settings = ref.watch(aiSettingsProvider);
  final apiKey = ref.watch(aiApiKeyProvider).value;
  if (apiKey == null || apiKey.trim().isEmpty) return null;

  final client = DeepSeekAsrClient(
    endpoint: settings.asrEndpoint,
    apiKey: apiKey.trim(),
  );
  ref.onDispose(client.dispose);
  return client;
});

final deepSeekOcrClientProvider = Provider<DeepSeekOcrClient?>((ref) {
  final settings = ref.watch(aiSettingsProvider);
  final apiKey = ref.watch(aiApiKeyProvider).value;
  if (apiKey == null || apiKey.trim().isEmpty) return null;

  final client = DeepSeekOcrClient(
    endpoint: settings.ocrEndpoint,
    apiKey: apiKey.trim(),
  );
  ref.onDispose(client.dispose);
  return client;
});

final attachmentPickerServiceProvider =
    Provider<AttachmentPickerService>((ref) {
  return NativeAttachmentPickerService();
});

final deepSeekTtsClientProvider = Provider<DeepSeekTtsClient?>((ref) {
  final settings = ref.watch(aiSettingsProvider);
  final apiKey = ref.watch(aiApiKeyProvider).value;
  if (apiKey == null || apiKey.trim().isEmpty) return null;

  final client = DeepSeekTtsClient(
    settings: settings,
    apiKey: apiKey.trim(),
  );
  ref.onDispose(client.dispose);
  return client;
});

final voiceRecorderServiceProvider = Provider<VoiceRecorderService>((ref) {
  final recorder = RecordVoiceRecorderService();
  ref.onDispose(() {
    recorder.dispose();
  });
  return recorder;
});

final streamingAudioPlayerProvider = Provider<StreamingAudioPlayer>((ref) {
  final player = SoLoudStreamingAudioPlayer();
  ref.onDispose(player.dispose);
  return player;
});

/// 运行时读到的应用版本。拿不到时兜底到常量。
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    return version.isEmpty ? UpdateConfig.fallbackVersion : version;
  } catch (_) {
    return UpdateConfig.fallbackVersion;
  }
});

final updateClientProvider = Provider<UpdateClient>((ref) {
  final client = UpdateClient();
  ref.onDispose(client.close);
  return client;
});

typedef UpdateInstallerFn = Future<InstallResult> Function(
  ReleaseInfo release, {
  http.Client? httpClient,
  void Function(double? progress)? onProgress,
  void Function(int receivedBytes, int? totalBytes)? onBytesProgress,
});

final updateInstallerProvider =
    Provider<UpdateInstallerFn>((ref) => installUpdate);

typedef OpenReleasePageFn = Future<InstallResult> Function(String htmlUrl);

final openReleasePageProvider =
    Provider<OpenReleasePageFn>((ref) => openReleasePage);

/// 检查结果常驻内存：启动时静默查一次。
final updateStatusProvider =
    NotifierProvider<UpdateStatusNotifier, UpdateStatus>(
  UpdateStatusNotifier.new,
);

class UpdateStatusNotifier extends Notifier<UpdateStatus> {
  @override
  UpdateStatus build() => const UpdateIdle();

  Future<void> check() async {
    if (state is UpdateChecking) return;
    state = const UpdateChecking();

    try {
      final current = await ref.read(appVersionProvider.future);
      final latest = await ref.read(updateClientProvider).checkLatest();

      if (latest == null) {
        state = UpdateUpToDate(currentVersion: current);
        return;
      }

      state = (!latest.isPrerelease && isNewerVersion(latest.tagName, current))
          ? UpdateAvailable(currentVersion: current, release: latest)
          : UpdateUpToDate(
              currentVersion: current,
              latestVersion: latest.tagName,
            );
    } on Object catch (e) {
      state = UpdateCheckFailed(
        e is UpdateException ? e.message : '检查更新失败',
      );
    }
  }
}
