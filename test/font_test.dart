import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:chatyuk/config/fonts.dart';

/// Uji deterministik pemetaan font global (tanpa memuat TextStyle
/// poppins/getFont yang butuh jaringan/asset font — itu diuji di HP).
///
/// Bug yang dijaga test ini: `AppFonts.family()`/`label()` dulu mengabaikan
/// `AppFonts.current` saat dipanggil tanpa argumen → token AppText selalu
/// jatuh ke jalur default (Poppins/Roboto) sehingga ganti font di admin
/// TIDAK berpengaruh (fitur tampak "tidak berubah").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  tearDown(() => AppFonts.current = AppFonts.defaultKey);

  group('AppFonts.family — pakai current bila tanpa argumen', () {
    test('default → null (tanpa override, Poppins + Roboto)', () {
      AppFonts.current = AppFonts.defaultKey;
      expect(AppFonts.family(), isNull);
    });

    test('inter → "Inter" (sans-serif modern)', () {
      AppFonts.current = 'inter';
      expect(AppFonts.family(), 'Inter');
    });

    test('lora → "Lora" (serif)', () {
      AppFonts.current = 'lora';
      expect(AppFonts.family(), 'Lora');
    });

    test('kembali ke default → null lagi', () {
      AppFonts.current = 'inter';
      expect(AppFonts.family(), 'Inter');
      AppFonts.current = AppFonts.defaultKey;
      expect(AppFonts.family(), isNull);
    });
  });

  group('AppFonts.family(key) — argumen eksplisit', () {
    test('inter/default/invalid', () {
      expect(AppFonts.family('inter'), 'Inter');
      expect(AppFonts.family('default'), isNull);
      expect(AppFonts.family('ngawur'), isNull);
    });
  });

  group('AppFonts.label — pakai current bila tanpa argumen', () {
    test('mengikuti current', () {
      AppFonts.current = 'inter';
      expect(AppFonts.label(), contains('Inter'));
      AppFonts.current = AppFonts.defaultKey;
      expect(AppFonts.label(), contains('Default'));
    });
  });

  group('AppFonts registry', () {
    test('isDefault', () {
      expect(AppFonts.isDefault('default'), isTrue);
      expect(AppFonts.isDefault('inter'), isFalse);
    });

    test('isSystem hanya true untuk key system', () {
      expect(AppFonts.isSystem('system'), isTrue);
      expect(AppFonts.isSystem('default'), isFalse);
      expect(AppFonts.isSystem('inter'), isFalse);
    });

    test('system ada di katalog, family null, resolve valid', () {
      expect(AppFonts.catalog.containsKey(AppFonts.systemKey), isTrue);
      expect(AppFonts.family('system'), isNull);
      expect(AppFonts.resolve('system'), 'system');
      expect(AppFonts.label('system'), contains('System'));
    });

    test('themeFontOverride system → null (pakai font platform)', () {
      AppFonts.current = AppFonts.systemKey;
      expect(AppFonts.themeFontOverride(), isNull);
      expect(AppFonts.family(), isNull);
      expect(AppFonts.isSystem(), isTrue);
    });

    test('resolve key tak dikenal → default', () {
      expect(AppFonts.resolve('ngawur'), 'default');
      expect(AppFonts.resolve(null), 'default');
      expect(AppFonts.resolve('inter'), 'inter');
    });

    test('setLocal mengubah current + resolve', () {
      AppFonts.setLocal('montserrat');
      expect(AppFonts.current, 'montserrat');
      expect(AppFonts.family(), 'Montserrat');
    });
  });

  group('themeFontOverride — jaring aman ThemeData', () {
    test('default → null (tanpa override)', () {
      AppFonts.current = AppFonts.defaultKey;
      expect(AppFonts.themeFontOverride(), isNull);
    });
  });

  group('font tipis baru (DM Sans, Figtree, Manrope)', () {
    test('terdaftar di katalog dengan family Google Fonts', () {
      expect(AppFonts.family('dm_sans'), 'DM Sans');
      expect(AppFonts.family('figtree'), 'Figtree');
      expect(AppFonts.family('manrope'), 'Manrope');
    });

    test('resolve/isDefault/isSystem: key utuh, bukan default', () {
      for (final k in ['dm_sans', 'figtree', 'manrope']) {
        expect(AppFonts.resolve(k), k);
        expect(AppFonts.isDefault(k), isFalse);
        expect(AppFonts.isSystem(k), isFalse);
      }
    });

    test('label memuat nama font (dipakai baris radio picker)', () {
      expect(AppFonts.label('dm_sans'), contains('DM Sans'));
      expect(AppFonts.label('figtree'), contains('Figtree'));
      expect(AppFonts.label('manrope'), contains('Manrope'));
    });

    test('lightWeight = w300 (cut tipis untuk pembanding)', () {
      expect(AppFonts.lightWeight, FontWeight.w300);
    });

    test('previewStyle menghormati bobot Light (key system, tanpa fetch)', () {
      final style = AppFonts.previewStyle(
        AppFonts.systemKey,
        size: 14,
        weight: AppFonts.lightWeight,
        color: const Color(0xFF000000),
        fallback: 'Roboto',
      );
      expect(style.fontWeight, FontWeight.w300);
      expect(style.fontSize, 14);
    });
  });
}
