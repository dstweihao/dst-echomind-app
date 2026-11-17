import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/settings/app_settings_store.dart';
import 'data/storage/file_store_factory.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final root = await _resolveStorageRoot();
  final themeMode = await _resolveThemeMode();

  runApp(
    ProviderScope(
      overrides: [
        initialStorageRootProvider.overrideWithValue(root),
        initialThemeModeProvider.overrideWithValue(themeMode),
      ],
      child: const EchoMindApp(),
    ),
  );
}

Future<String> _resolveStorageRoot() async {
  try {
    final saved = await AppSettingsStore().loadStorageRoot();
    if (saved != null && saved.isNotEmpty) return saved;
  } catch (_) {}

  try {
    return await defaultRootPath();
  } catch (_) {
    return '';
  }
}

Future<ThemeMode> _resolveThemeMode() async {
  try {
    return await AppSettingsStore().loadThemeMode();
  } catch (_) {
    return ThemeMode.light;
  }
}
