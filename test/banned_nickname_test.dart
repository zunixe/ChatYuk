import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/utils.dart';

void main() {
  group('isBannedNickname', () {
    test('varian zaini/hafid diblokir', () {
      for (final n in [
        'ZAINI',
        'hafid',
        'Zaini Hafid',
        'Hafid Zaini',
        'ZAINIHAFID',
        'zaini-hafid',
        'zaini_hafid',
        'ZaInI',
        'XXhafidXX',
        'ZainiGanteng123',
      ]) {
        expect(isBannedNickname(n), isTrue, reason: n);
      }
    });

    test('nama biasa lolos', () {
      for (final n in ['Zain', 'Hafi', 'Ani', 'Budi', 'Sari123', '']) {
        expect(isBannedNickname(n), isFalse, reason: n);
      }
    });
  });
}
