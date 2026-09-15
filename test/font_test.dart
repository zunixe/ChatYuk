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
}
