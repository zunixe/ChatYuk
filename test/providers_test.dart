import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/providers/riverpod/locale_provider.dart';
import 'package:chatyuk/providers/riverpod/nav_provider.dart';
import 'package:chatyuk/providers/riverpod/theme_provider.dart';

import 'test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NavNotifier', () {
    test('goTo pindah tab, sama = no-op', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final nav = c.read(navProvider.notifier);
      expect(c.read(navProvider), 0);
      nav.goTo(2);
      expect(c.read(navProvider), 2);
      nav.goTo(2);
      expect(c.read(navProvider), 2);
    });
  });

  group('LocaleNotifier', () {
    test('default id, setLang persist', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(localeProvider.notifier);
      expect(c.read(localeProvider).lang, 'id');
      expect(c.read(localeProvider).isId, isTrue);
      expect(c.read(localeProvider).s.btnSave, 'Simpan');

      await n.setLang('en');
      expect(c.read(localeProvider).lang, 'en');
      expect(c.read(localeProvider).isId, isFalse);
      expect(c.read(localeProvider).s.btnSave, 'Save');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_lang'), 'en');
    });

    test('init baca preferensi tersimpan', () async {
      SharedPreferences.setMockInitialValues({'app_lang': 'en'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(localeProvider.notifier).init();
      expect(c.read(localeProvider).lang, 'en');
    });

    test('setLangFromCountry: Indonesia→id, lain→en, hormati preferensi',
        () async {
      SharedPreferences.setMockInitialValues({});
      final c1 = ProviderContainer();
      addTearDown(c1.dispose);
      await c1.read(localeProvider.notifier).setLangFromCountry('Malaysia');
      expect(c1.read(localeProvider).lang, 'en');

      SharedPreferences.setMockInitialValues({});
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      await c2.read(localeProvider.notifier).setLangFromCountry('Indonesia');
      expect(c2.read(localeProvider).lang, 'id');

      SharedPreferences.setMockInitialValues({'app_lang': 'en'});
      final c3 = ProviderContainer();
      addTearDown(c3.dispose);
      await c3.read(localeProvider.notifier).init();
      await c3.read(localeProvider.notifier).setLangFromCountry('Indonesia');
      expect(c3.read(localeProvider).lang, 'en');
    });
  });

  group('ThemeNotifier', () {
    tearDown(() {
      resetFontForTest();
      AppTheme.isDark = true;
    });

    test('default gelap, setDark persist + themeMode', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(themeProvider.notifier);
      expect(c.read(themeProvider).isDark, isTrue);
      expect(c.read(themeProvider).themeMode, ThemeMode.dark);

      await n.setDark(false);
      expect(c.read(themeProvider).isDark, isFalse);
      expect(c.read(themeProvider).themeMode, ThemeMode.light);
      expect(AppTheme.isDark, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('app_theme_dark'), isFalse);

      await n.setDark(true);
      expect(AppTheme.isDark, isTrue);
    });

    test('init baca preferensi tersimpan', () async {
      SharedPreferences.setMockInitialValues({'app_theme_dark': false});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(themeProvider.notifier).init();
      expect(c.read(themeProvider).isDark, isFalse);
      expect(AppTheme.isDark, isFalse);
      AppTheme.isDark = true;
    });

    test('init memuat font tersimpan (dependensi rebuild MaterialApp)',
        () async {
      SharedPreferences.setMockInitialValues({
        'app_theme_dark': false,
        'app_font_family': 'lora',
      });
      AppFonts.setLocal(AppFonts.defaultKey);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(themeProvider.notifier).init();
      expect(AppFonts.current, 'lora');
      expect(c.read(themeProvider).fontKey, 'lora');
      expect(c.read(themeProvider).isDark, isFalse);
    });

    test('font tak dikenal di prefs → fallback default', () async {
      SharedPreferences.setMockInitialValues({'app_font_family': 'ngawur'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(themeProvider.notifier).init();
      expect(c.read(themeProvider).fontKey, AppFonts.defaultKey);
    });
  });
}
