import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';

/// Kontrol mode terang/gelap — persist di SharedPreferences.
class ThemeProvider extends ChangeNotifier {
  static const _prefKey = 'app_theme_dark';
  bool _dark = false;
  bool _initialized = false;

  bool get isDark => _dark;
  ThemeMode get themeMode => _dark ? ThemeMode.dark : ThemeMode.light;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _dark = prefs.getBool(_prefKey) ?? false;
    AppTheme.isDark = _dark;
    _initialized = true;
    notifyListeners();
  }

  Future<void> setDark(bool value) async {
    if (_dark == value) return;
    _dark = value;
    AppTheme.isDark = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    notifyListeners();
  }
}