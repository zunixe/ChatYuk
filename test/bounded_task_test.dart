
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/bounded_task.dart';

/// Mengunci pembatasan konkurensi upload (FASE 2 C).
void main() {
  test('konkurensi maksimal tidak pernah terlampaui', () async {
    var active = 0;
    var peak = 0;
    final done = <int>[];
    await runBounded<int>(
      items: List.generate(10, (i) => i),
      maxConcurrent: 3,
      run: (item, i) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        done.add(item);
        active--;
      },
    );
    expect(peak, lessThanOrEqualTo(3), reason: 'maks 3 bersamaan');
    expect(peak, greaterThan(1), reason: 'benar-benar paralel (bukan serial)');
    expect(done.toSet(), {0, 1, 2, 3, 4, 5, 6, 7, 8, 9});
  });

  test('urutan indeks diteruskan benar (stabil untuk hasil per-indeks)',
      () async {
    final seen = <int, int>{};
    await runBounded<int>(
      items: List.generate(5, (i) => i * 10),
      maxConcurrent: 2,
      run: (item, i) async => seen[i] = item,
    );
    expect(seen, {0: 0, 1: 10, 2: 20, 3: 30, 4: 40});
  });

  test('daftar kosong → tidak memanggil apa pun', () async {
    var calls = 0;
    await runBounded<int>(
      items: const [],
      maxConcurrent: 3,
      run: (_, _) async => calls++,
    );
    expect(calls, 0);
  });

  test('maxConcurrent > jumlah item → semua jalan sekali', () async {
    var calls = 0;
    await runBounded<int>(
      items: [1, 2],
      maxConcurrent: 99,
      run: (_, _) async => calls++,
    );
    expect(calls, 2);
  });
}
