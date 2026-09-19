import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/core/admin_gate.dart';

// Catatan: pengujian katalog font (AppFonts) tinggal di `font_test.dart` —
// satu rumah supaya tidak ada dua versi ekspektasi yang bisa berbeda.

void main() {
  group('token tipografi AppText (8 ukuran resmi)', () {
    test('token plain (tanpa GoogleFonts) sesuai skala', () {
      expect(AppText.micro.fontSize, 10);
      expect(AppText.caption.fontSize, 11);
      expect(AppText.label.fontSize, 12);
      expect(AppText.bodySmall.fontSize, 12);
      expect(AppText.body.fontSize, 14);
      expect(AppText.bodyStrong.fontSize, 14);
    });

    test('label/bodySmall beda weight (hierarki via weight)', () {
      expect(AppText.label.fontWeight, isNot(AppText.bodySmall.fontWeight));
    });

    test(
      'token Poppins (button/title/headline/display) sesuai skala via sumber',
      () {
        final src = File('lib/config/theme.dart').readAsStringSync();
        // Token judul/CTA lewat helper _brand; saat default memakai
        // GoogleFonts.poppins(fontSize: <size>, fontWeight: <w>).
        int brandSizeFor(String getter) {
          // Ambil body getter (mis. `static TextStyle get title =>`), lalu
          // temukan pasangan _brand(size, weight, ...) tepat setelahnya —
          // toleran newline/spasi (dart format boleh memecah baris).
          final getterIdx = src.indexOf('static TextStyle get $getter =>');
          expect(
            getterIdx,
            isNot(-1),
            reason: '$getter tidak memakai _brand di theme.dart',
          );
          final after = src.substring(getterIdx);
          final m = RegExp(
            r'_brand\(\s*([0-9.]+)\s*,\s*FontWeight\.w[0-9]+',
            multiLine: true,
          ).firstMatch(after);
          expect(m, isNotNull, reason: '$getter: _brand args tidak ditemukan');
          return double.parse(m!.group(1)!).toInt();
        }

        expect(brandSizeFor('button'), 16);
        expect(brandSizeFor('titleEmphasis'), 16);
        expect(brandSizeFor('title'), 17);
        expect(brandSizeFor('headline'), 20);
        expect(brandSizeFor('display'), 24);

        // Sumber tetap memuat Poppins (jalur default).
        expect(src.contains('GoogleFonts.poppins('), isTrue);
      },
    );

    test('blok kode tetap monospace (tidak ikut font global)', () {
      expect(AppText.code.fontFamily, 'monospace');
    });
  });

  group('AppGlyph', () {
    test('skala emoji 20/24/28/40', () {
      expect(AppGlyph.sm, 20);
      expect(AppGlyph.md, 24);
      expect(AppGlyph.lg, 28);
      expect(AppGlyph.xl, 40);
    });

    test('avatarInitial proporsional diameter * 0.38', () {
      expect(AppGlyph.avatarInitial(100), 38);
      expect(AppGlyph.avatarInitial(50), 19);
    });
  });

  group('StoryText', () {
    test('size ikut skala 16/20/24', () {
      expect(StoryText.size(0), 16);
      expect(StoryText.size(1), 20);
      expect(StoryText.size(2), 24);
      expect(StoryText.size(99), 24);
    });
  });

  group('AdminGate', () {
    test('isRealAdmin hanya email admin', () {
      expect(AdminGate.isRealAdmin('zunixe@gmail.com'), isTrue);
      expect(AdminGate.isRealAdmin('user@gmail.com'), isFalse);
      expect(AdminGate.isRealAdmin(null), isFalse);
    });
  });

  // Konsistensi indikator status — mencegah regresi ke 5 definisi _statusColor
  // + belasan nilai inline yang berbeda antar layar (lihat theme.dart).
  group('AppTheme.statusColor (satu sumber)', () {
    test('online/idle/offline memakai token resmi', () {
      expect(AppTheme.statusColor('online'), AppTheme.online);
      expect(AppTheme.statusColor('idle'), AppTheme.idle);
      expect(AppTheme.statusColor('offline'), AppTheme.offline);
    });

    test('null & status tak dikenal → offline (bukan crash)', () {
      expect(AppTheme.statusColor(null), AppTheme.offline);
      expect(AppTheme.statusColor('invisible'), AppTheme.offline);
      expect(AppTheme.statusColor(''), AppTheme.offline);
    });
  });

  group('avatarBg (opaque, konsisten antar permukaan)', () {
    test('light & dark tidak transparan', () {
      AppTheme.isDark = false;
      expect(AppTheme.avatarBg.a, 1.0);
      AppTheme.isDark = true;
      expect(AppTheme.avatarBg.a, 1.0);
      AppTheme.isDark = false;
    });
  });
}
