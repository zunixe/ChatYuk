import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/strings.dart';

class LocaleProvider extends ChangeNotifier {
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String _lang = 'id';
  bool _initialized = false;

  String get lang => _lang;
  bool get isId => _lang == 'id';
  S get s => S(isId: _lang == 'id');

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _lang = prefs.getString('app_lang') ?? 'id';
    _initialized = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> setLang(String lang) async {
    if (_lang == lang) return;
    _lang = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_lang', lang);
    if (!_disposed) notifyListeners();
  }

  /// Set bahasa dari country name (dari geo detection).
  /// Hanya set jika belum ada saved preference.
  Future<void> setLangFromCountry(String countryName) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('app_lang')) return;
    final lang = countryName == 'Indonesia' ? 'id' : 'en';
    await setLang(lang);
  }
}
