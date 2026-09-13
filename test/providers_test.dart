import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/nav_provider.dart';
import 'package:chatyuk/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NavProvider', () {
    test('goTo pindah tab + notify, sama = no-op', () {
      final nav = NavProvider();
      var notified = 0;
      nav.addListener(() => notified++);
      expect(nav.tab, 0);
      nav.goTo(2);
      expect(nav.tab, 2);
      expect(notified, 1);
      nav.goTo(2);
      expect(notified, 1);
      nav.dispose();
    });
  });

  group('LocaleProvider', () {
    test('default id, setLang persist + notify', () async {
      SharedPreferences.setMockInitialValues({});
      final lp = LocaleProvider();
      expect(lp.lang, 'id');
      expect(lp.isId, isTrue);
      expect(lp.s.btnSave, 'Simpan');

      var notified = 0;
      lp.addListener(() => notified++);
      await lp.setLang('en');
      expect(lp.lang, 'en');
      expect(lp.isId, isFalse);
      expect(lp.s.btnSave, 'Save');
      expect(notified, 1);

      await lp.setLang('en');
      expect(notified, 1);
      lp.dispose();
    });

    test('init baca preferensi tersimpan', () async {
      SharedPreferences.setMockInitialValues({'app_lang': 'en'});
      final lp = LocaleProvider();
      await lp.init();
      expect(lp.lang, 'en');
      await lp.init();
      expect(lp.lang, 'en');
      lp.dispose();
    });

    test('setLangFromCountry: Indonesia→id, lain→en, hormati preferensi', () async {
      SharedPreferences.setMockInitialValues({});
      final lp = LocaleProvider();
      await lp.setLangFromCountry('Malaysia');
      expect(lp.lang, 'en');

      SharedPreferences.setMockInitialValues({});
      final lp2 = LocaleProvider();
      await lp2.setLangFromCountry('Indonesia');
      expect(lp2.lang, 'id');

      SharedPreferences.setMockInitialValues({'app_lang': 'en'});
      final lp3 = LocaleProvider();
      await lp3.init();
      await lp3.setLangFromCountry('Indonesia');
      expect(lp3.lang, 'en');
      lp.dispose();
      lp2.dispose();
      lp3.dispose();
    });
  });

  group('ThemeProvider', () {
    test('default gelap, setDark persist + themeMode', () async {
      SharedPreferences.setMockInitialValues({});
      final tp = ThemeProvider();
      expect(tp.isDark, isTrue);
      expect(tp.themeMode, ThemeMode.dark);

      await tp.setDark(false);
      expect(tp.isDark, isFalse);
      expect(tp.themeMode, ThemeMode.light);
      expect(AppTheme.isDark, isFalse);

      await tp.setDark(false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('app_theme_dark'), isFalse);

      await tp.setDark(true);
      expect(AppTheme.isDark, isTrue);
      tp.dispose();
    });

    test('init baca preferensi tersimpan', () async {
      SharedPreferences.setMockInitialValues({'app_theme_dark': false});
      final tp = ThemeProvider();
      await tp.init();
      expect(tp.isDark, isFalse);
      expect(AppTheme.isDark, isFalse);
      tp.dispose();
      AppTheme.isDark = true;
    });
  });
}
