import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/chat_video_bubble.dart';

/// Minta user: kartu FOTO SEKALI-LIHAT ukurannya harus SAMA dengan kartu foto
/// yang sudah KEDALUWARSA (tidak melompat saat foto mengunci).
void main() {
  test('kartu terkunci punya satu sumber ukuran', () {
    expect(ViewOnceLockedCard.cardWidth, 200);
    expect(ViewOnceLockedCard.cardHeight, 140);
  });

  test('GUARD: kartu foto sekali-lihat memakai ukuran ViewOnceLockedCard', () {
    final src = File(
      'lib/widgets/message/view_once_image.dart',
    ).readAsStringSync();
    expect(src.contains('ViewOnceLockedCard.cardWidth'), isTrue);
    expect(src.contains('ViewOnceLockedCard.cardHeight'), isTrue);
    // Tidak boleh ada ukuran proporsional lama (maks 280) yang tertinggal.
    expect(src.contains('> 280'), isFalse);
  });
}
