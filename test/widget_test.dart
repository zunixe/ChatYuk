import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/core/admin_gate.dart';

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

    test('token Poppins (button/title/headline/display) sesuai skala via sumber', () {
      final src = File('lib/config/theme.dart').readAsStringSync();
      int fontSizeFor(String getter) {
        final m = RegExp('static TextStyle get $getter => GoogleFonts.poppins\\(\\s*fontSize: ([0-9.]+),',
                multiLine: true)
            .firstMatch(src);
        expect(m, isNotNull, reason: '$getter tidak ditemukan di theme.dart');
        return double.parse(m!.group(1)!).toInt();
      }

      expect(fontSizeFor('button'), 16);
      expect(fontSizeFor('titleEmphasis'), 16);
      expect(fontSizeFor('title'), 17);
      expect(fontSizeFor('headline'), 20);
      expect(fontSizeFor('display'), 24);
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
}
