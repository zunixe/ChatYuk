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
    // Ukuran kartu foto lewat helper murni `viewOncePhotoSize` (potret boleh
    // lebih tinggi → tidak letterbox) dan gambar di-`cover` (tanpa bilah).
    expect(src.contains('viewOncePhotoSize('), isTrue);
    expect(src.contains('BoxFit.cover'), isTrue);
    // Tidak ada lagi ukuran hardcode 220 lama.
    expect(src.contains('width: 220'), isFalse);
  });

  test('GUARD: penerima TIDAK merender foto di bubble — tap langsung viewer', () {
    final src = File(
      'lib/widgets/message/view_once_image.dart',
    ).readAsStringSync();
    // Hanya 3 `Image.memory`: kartu PENGIRIM, `_InstantBytes` (pengirim), dan
    // monitor admin. Penerima tidak boleh punya jalur render foto di bubble
    // (bisa dilihat berulang tanpa membuka viewer — minta user 2026-10-20).
    final imageMemories = RegExp(r'Image\.memory\(').allMatches(src).length;
    expect(imageMemories, 3);
    expect(src.contains('_startViewingAndOpen'), isTrue);
    expect(src.contains('onTap: _openViewer'), isTrue);
  });
}
