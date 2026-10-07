import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/strings.dart';

/// Mirror language global — dibaca kode NON-WIDGET (mis. builder notifikasi
/// di `main.dart`) yang butuh `S` sebelum/tanpa BuildContext. Nilai ini
/// di-update oleh [LocaleNotifier] (satu-satunya sumber kebenaran).
class AppLocale {
  AppLocale._();

  static const String prefKey = 'app_lang';
  static String lang = 'id';

  static bool get isId => lang == 'id';
  static S get s => S(isId: isId);

  /// Baca preferensi tersimpan ke mirror (dipanggil saat boot).
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    lang = prefs.getString(prefKey) ?? 'id';
  }

  static Future<void> set(String value) async {
    lang = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, value);
  }
}

/// State bahasa aktif (Riverpod).
class LocaleState {
  final String lang;
  const LocaleState(this.lang);

  bool get isId => lang == 'id';
  S get s => S(isId: isId);

  @override
  bool operator ==(Object other) => other is LocaleState && other.lang == lang;
  @override
  int get hashCode => lang.hashCode;
}

class LocaleNotifier extends Notifier<LocaleState> {
  @override
  LocaleState build() => LocaleState(AppLocale.lang);

  Future<void> init() async {
    await AppLocale.init();
    state = LocaleState(AppLocale.lang);
  }

  Future<void> setLang(String lang) async {
    if (state.lang == lang) return;
    await AppLocale.set(lang);
    state = LocaleState(lang);
  }

  /// Set bahasa dari country name (dari geo detection).
  /// Hanya set jika belum ada saved preference.
  Future<void> setLangFromCountry(String countryName) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(AppLocale.prefKey)) return;
    final lang = countryName == 'Indonesia' ? 'id' : 'en';
    await setLang(lang);
  }
}

final localeProvider =
    NotifierProvider<LocaleNotifier, LocaleState>(LocaleNotifier.new);
