import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/utils.dart';

void main() {
  test('poin angka sebaris jadi paragraf', () {
    const t = 'Data: Rp500 jt beli emas. 2. Alasan: momentum bullish. 3. Risiko turun.';
    final o = formatChatLists(t);
    expect(o.contains('\n\n2. Alasan'), isTrue);
    expect(o.contains('\n\n3. Risiko'), isTrue);
    expect(o.contains('Rp500'), isTrue);
  });

  test('sub-poin kurung menjorok', () {
    const t = '3. Risiko: (a) USD menguat. (b) Fed hawkish.';
    final o = formatChatLists(t);
    expect(o.contains('\n  (a) USD'), isTrue);
    expect(o.contains('\n  (b) Fed'), isTrue);
  });

  test('desimal, jam, harga tidak kepecah', () {
    const t = 'Versi 3.5 jam 14.00 harga Rp 50.000 ya.';
    expect(formatChatLists(t), t);
  });

  test('sudah rapi tidak berubah', () {
    const t = '1. Data\n\n2. Alasan\n  (a) X\n  (b) Y';
    expect(formatChatLists(t), t);
  });

  test('blok kode dilewati', () {
    const t = 'lihat:\n```\n1. bukan list 2. ini kode\n```\nlanjut 1. A 2. B ya.';
    final o = formatChatLists(t);
    expect(o.contains('1. bukan list 2. ini kode'), isTrue);
    expect(o.contains('\n\n1. A'), isTrue);
  });
}
