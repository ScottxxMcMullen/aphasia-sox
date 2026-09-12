import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two things the app remembers between launches. Deliberately this
/// narrow — it is not a general preferences layer, and nothing else in the
/// app has state worth persisting.
class SettingsStore {
  static const _themeKey = 'theme_mode';
  static const _syncedKey = 'last_synced_at';

  Future<ThemeMode> themeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

  Future<DateTime?> lastSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_syncedKey);
    return raw == null ? null : DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> markSynced() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_syncedKey, DateTime.now().millisecondsSinceEpoch);
  }
}
