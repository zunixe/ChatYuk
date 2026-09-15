import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/theme.dart';

/// Uji skala font chat (slider di profil): clamp, normalisasi, persist,
/// dan token AppText.chatBody/chatTime ikut terskala.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => ChatTextScale.setLocal(1.0));

  group('ChatTextScale.resolve', () {
    test('null / NaN / infinite → 1.0', () {
      expect(ChatTextScale.resolve(null), 1.0);
      expect(ChatTextScale.resolve(double.nan), 1.0);
      expect(ChatTextScale.resolve(double.infinity), 1.0);
    });

    test('clamp ke [min,max]', () {
      expect(ChatTextScale.resolve(0.1), ChatTextScale.min);
      expect(ChatTextScale.resolve(9.0), ChatTextScale.max);
      expect(ChatTextScale.resolve(1.2), 1.2);
    });

    test('dibulatkan 2 desimal', () {
      expect(ChatTextScale.resolve(1.23456), 1.23);
    });
  });

  group('ChatTextScale.scale', () {
    test('multiplier diterapkan ke basis', () {
      ChatTextScale.setLocal(1.0);
      expect(ChatTextScale.scale(14), 14.0);
      ChatTextScale.setLocal(1.2);
      expect(ChatTextScale.scale(10), closeTo(12.0, 0.001));
    });

    test('nilai ekstrem tetap ter-clamp', () {
      ChatTextScale.setLocal(5.0); // resolve → max
      expect(ChatTextScale.scale(10), closeTo(14.0, 0.001));
    });
  });

  group('AppText token ikut skala', () {
    test('chatBody membesar saat scale naik', () {
      ChatTextScale.setLocal(1.0);
      final base = AppText.chatBody.fontSize!;
      ChatTextScale.setLocal(1.4);
      final big = AppText.chatBody.fontSize!;
      expect(big, greaterThan(base));
      expect(big, closeTo(14 * 1.4, 0.01));
    });

    test('chatTime = 10 × scale', () {
      ChatTextScale.setLocal(1.0);
      expect(AppText.chatTime.fontSize, 10.0);
    });

    test('percent + notifier sinkron', () {
      ChatTextScale.setLocal(1.25);
      expect(ChatTextScale.percent, 125);
      expect(ChatTextScale.notifier.value, 1.25);
    });
  });
}
