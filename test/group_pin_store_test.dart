import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/core/cache/group_pin_store.dart';

/// Regresi: sematan GRUP di daftar Pesan (lokal per perangkat) + urutannya.
void main() {
  setUp(GroupPinStore.resetForTest);
  tearDown(GroupPinStore.resetForTest);

  test('toggle: semat lalu lepas', () {
    expect(GroupPinStore.isPinned('g1'), isFalse);
    expect(GroupPinStore.toggle('g1'), isTrue);
    expect(GroupPinStore.isPinned('g1'), isTrue);
    expect(GroupPinStore.toggle('g1'), isFalse);
    expect(GroupPinStore.isPinned('g1'), isFalse);
  });

  test('remove membuang sematan', () {
    GroupPinStore.toggle('g1');
    GroupPinStore.remove('g1');
    expect(GroupPinStore.isPinned('g1'), isFalse);
  });

  test('urutan: tersemat di atas, terbaru disematkan dulu', () async {
    final t0 = DateTime(2026, 1, 1);
    // g2 disematkan lebih dulu, g3 belakangan.
    GroupPinStore.toggle('g2');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    GroupPinStore.toggle('g3');
    final ids = ['g1', 'g2', 'g3']
      ..sort((a, b) => GroupPinStore.compareGroups(
            a,
            t0.add(Duration(days: a == 'g1' ? 3 : 0)),
            b,
            t0.add(Duration(days: b == 'g1' ? 3 : 0)),
          ));
    // g3 & g2 tersemat (g3 paling baru) → di atas; g1 tanpa sematan terakhir.
    expect(ids, ['g3', 'g2', 'g1']);
  });

  test('tanpa sematan: urut aktivitas terbaru (lastAt desc)', () {
    final ids = ['a', 'b', 'c']
      ..sort((x, y) => GroupPinStore.compareGroups(
            x,
            DateTime(2026, 1, x == 'a' ? 1 : (x == 'b' ? 3 : 2)),
            y,
            DateTime(2026, 1, y == 'a' ? 1 : (y == 'b' ? 3 : 2)),
          ));
    expect(ids, ['b', 'c', 'a']);
  });
}
