import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's chosen theme mode (system / light / dark) and persists it
/// across launches. Exposed as a [ValueNotifier] so the app rebuilds on change.
class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _key = 'themeMode';

  final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(ThemeMode.system);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      mode.value = _fromId(prefs.getString(_key));
    } catch (_) {
      // Keep the default (system) if storage is unavailable.
    }
  }

  Future<void> set(ThemeMode m) async {
    mode.value = m;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, m.name);
    } catch (_) {}
  }

  static ThemeMode _fromId(String? id) => switch (id) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
