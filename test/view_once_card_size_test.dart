import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/chat_video_bubble.dart';

/// Kartu terkunci (video/kedaluwarsa umum) tetap punya default 200×140,
/// sedangkan kartu FOTO sekali-lihat harus mengikuti ukuran foto biasa.
void main() {
  test('default kartu terkunci tetap 200×140 (untuk video)', () {
    expect(ViewOnceLockedCard.cardWidth, 200);
    expect(ViewOnceLockedCard.cardHeight, 140);
  });

  test('GUARD: kartu foto sekali-lihat memakai chatMediaWidth (foto biasa)', () {
    final src = File(
      'lib/widgets/message/view_once_image.dart',
    ).readAsStringSync();
    // Satu sumber ukuran: lebar foto biasa (72% layar) + tinggi rasio foto.
    expect(src.contains('chatMediaWidth('), isTrue);
    expect(src.contains('chatPhotoSize('), isTrue);
    // Tidak boleh lagi mengunci 200×140 atau 220.
    expect(src.contains('ViewOnceLockedCard.cardWidth'), isFalse);
    expect(src.contains('width: 220'), isFalse);
  });
}
