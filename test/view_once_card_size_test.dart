import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/chat_video_bubble.dart';

/// Aturan ukuran kartu view-once:
///  - kunci/pembuka/kedaluwarsa → TETAP KECIL 200×140
///  - foto yang sedang ditampilkan → ukuran foto biasa (72% layar + rasio foto)
void main() {
  test('default kartu terkunci 200×140', () {
    expect(ViewOnceLockedCard.cardWidth, 200);
    expect(ViewOnceLockedCard.cardHeight, 140);
  });

  test('GUARD: kartu kecil memakai konstanta; foto memakai chatMediaWidth', () {
    final src = File(
      'lib/widgets/message/view_once_image.dart',
    ).readAsStringSync();
    // Kartu pembuka & terkunci kembali kecil (bukan ikut ukuran foto).
    expect(src.contains('ViewOnceLockedCard.cardWidth'), isTrue);
    expect(src.contains('ViewOnceLockedCard.cardHeight'), isTrue);
    // Kartu yang menampilkan foto memakai lebar foto biasa + rasio foto.
    expect(src.contains('chatMediaWidth('), isTrue);
    expect(src.contains('chatPhotoSize('), isTrue);
    // Tidak ada lagi ukuran hardcode 220 lama.
    expect(src.contains('width: 220'), isFalse);
  });
}
