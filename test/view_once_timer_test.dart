import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/private_chat_message.dart';

/// Aturan durasi view-once (durationMs pesan):
/// null/negatif = legacy 10 dtk, 0 = sampai ditutup (1x), N = N detik.
void main() {
  group('resolveViewOnceSecs', () {
    test('null → 10 (legacy)', () => expect(resolveViewOnceSecs(null), 10));
    test('negatif → 10', () {
      expect(resolveViewOnceSecs(-1), 10);
      expect(resolveViewOnceSecs(-99), 10);
    });
    test('0 → 0 (1x sampai ditutup)', () {
      expect(resolveViewOnceSecs(0), 0);
    });
    test('N → N detik', () {
      expect(resolveViewOnceSecs(3), 3);
      expect(resolveViewOnceSecs(10), 10);
    });
  });
}
