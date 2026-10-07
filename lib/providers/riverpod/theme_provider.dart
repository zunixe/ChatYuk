import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme.dart';
import '../../config/fonts.dart';

/// Mode terang/gelap + key font global (Riverpod).
///
/// Migrasi dari ChangeNotifier → Notifier. State = record (isDark, fontKey)
/// supaya rebuild granular (hanya saat salah satu berubah).
class ThemeState {
  final bool isDark;
  final String fontKey;
  const ThemeState(this.isDark, this.fontKey);

  ThemeMode get themeMode => isDark ? ThemeMode.dark : ThemeMode.light;

  @override
  bool operator ==(Object other) =>
      other is ThemeState && other.isDark == isDark && other.fontKey == fontKey;
  @override
  int get hashCode => Object.hash(isDark, fontKey);
}

class ThemeNotifier extends Notifier<ThemeState> {
  static const _prefKey = 'app_theme_dark';
  bool _initialized = false;

  @override
  ThemeState build() {
    return ThemeState(true, AppFonts.current);
  }

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final dark = prefs.getBool(_prefKey) ?? true;
    AppTheme.isDark = dark;
    await AppFonts.init();
    _initialized = true;
    state = ThemeState(dark, AppFonts.current);
  }

  Future<void> setDark(bool value) async {
    if (state.isDark == value) return;
    state = ThemeState(value, state.fontKey);
    AppTheme.isDark = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }
}

final themeProvider =
    NotifierProvider<ThemeNotifier, ThemeState>(ThemeNotifier.new);
