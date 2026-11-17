import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 非敏感的本地设备偏好存储
class AppSettingsStore {
  static const _keyStorageRoot = 'storage_root_path';
  static const _keyThemeMode = 'theme_mode';

  Future<String?> loadStorageRoot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(_keyStorageRoot);
      return (path == null || path.trim().isEmpty) ? null : path.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveStorageRoot(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStorageRoot, path.trim());
  }

  Future<void> clearStorageRoot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyStorageRoot);
  }

  Future<ThemeMode> loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyThemeMode);
      return switch (raw) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };
    } catch (_) {
      return ThemeMode.light;
    }
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode.name);
  }
}
