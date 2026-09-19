import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/chat/read_receipt.dart';

/// REGRESSION (docs/FEATURE_MAP.md §3a):
/// - Read receipt WAJIB monoton maju — nilai null/lebih tua tidak boleh
///   menurunkan status (dulu: centang-2 balik jadi centang-1 lalu muncul lagi).
/// - Batas inklusif `<=` — pesan dengan timestamp PERSIS sama dengan waktu
///   baca ikut centang-2 (dulu pakai `isBefore` ketat → tidak masuk).
void main() {
  final t1 = DateTime(2026, 9, 19, 10, 0, 0);
  final t2 = DateTime(2026, 9, 19, 10, 5, 0);
  final t3 = DateTime(2026, 9, 19, 10, 10, 0);

  group('ReadReceipt.merge (monoton maju)', () {
    test('incoming null → pertahankan yang lama', () {
      expect(ReadReceipt.merge(t2, null), t2);
      expect(ReadReceipt.merge(null, null), isNull);
    });

    test('incoming lebih tua → TIDAK mundur', () {
      expect(ReadReceipt.merge(t2, t1), t2);
    });

    test('incoming lebih baru → maju', () {
      expect(ReadReceipt.merge(t1, t2), t2);
    });

    test('incoming sama → tetap sama (idempoten)', () {
      expect(ReadReceipt.merge(t2, t2), t2);
    });

    test('current null → pakai incoming', () {
      expect(ReadReceipt.merge(null, t2), t2);
    });
  });

  group('ReadReceipt.best (gabung banyak sumber)', () {
    test('ambil yang terbaru dari snapshot live + cache', () {
      expect(ReadReceipt.best([t1, t3, t2]), t3);
    });

    test('abaikan null & tak memundurkan', () {
      expect(ReadReceipt.best([null, t2, null, t1]), t2);
    });

    test('semua null → null', () {
      expect(ReadReceipt.best([null, null]), isNull);
    });

    test('kosong → null', () {
      expect(ReadReceipt.best(const []), isNull);
    });
  });

  group('ReadReceipt.isRead (batas inklusif)', () {
    test('pesan lebih tua dari last-read → terbaca', () {
      expect(ReadReceipt.isRead(t1, t2), isTrue);
    });

    test('pesan PERSIS sama waktu baca → terbaca (regresi isBefore ketat)', () {
      expect(ReadReceipt.isRead(t2, t2), isTrue);
    });

    test('pesan lebih baru dari last-read → belum terbaca', () {
      expect(ReadReceipt.isRead(t3, t2), isFalse);
    });

    test('last-read null → belum terbaca', () {
      expect(ReadReceipt.isRead(t1, null), isFalse);
    });
  });

  group('ReadReceipt.parse', () {
    test('DateTime diteruskan apa adanya', () {
      expect(ReadReceipt.parse(t2), t2);
    });

    test('ISO string diparse', () {
      expect(ReadReceipt.parse(t2.toIso8601String()), t2);
    });

    test('null → null', () {
      expect(ReadReceipt.parse(null), isNull);
    });

    test('string tak valid → null (bukan epoch)', () {
      expect(ReadReceipt.parse('bukan-tanggal'), isNull);
    });
  });
}
