import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/utils.dart';

/// Test untuk fix "nickname sudah digunakan padahal baru" —
/// cek ketersediaan nickname kini CASE-INSENSITIVE dan wildcard di-escape.
void main() {
  group('escapeIlikePattern', () {
    test('nickname biasa tidak berubah', () {
      expect(escapeIlikePattern('Budi'), 'Budi');
      expect(escapeIlikePattern('Sari123'), 'Sari123');
      expect(escapeIlikePattern('John Doe'), 'John Doe');
    });

    test('wildcard % di-escape', () {
      expect(escapeIlikePattern('100%'), r'100\%');
    });

    test('wildcard _ di-escape', () {
      expect(escapeIlikePattern('a_b'), r'a\_b');
    });

    test('backslash di-escape lebih dulu', () {
      expect(escapeIlikePattern(r'a\b'), r'a\\b');
    });

    test('kombinasi', () {
      expect(escapeIlikePattern(r'Nor_%mal\'), r'Nor\_\%mal\\');
    });
  });
}
