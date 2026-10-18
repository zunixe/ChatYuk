import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// GUARD aturan kartu bubble chat — lihat `docs/UI_CONSISTENCY.md`.
///
/// Regresi nyata (2026-10-18): kartu KONTAK tidak terdaftar sebagai kartu →
/// padding bubble 10 (teks) + padding dalam 10 = lebih menjorok daripada
/// file/lokasi (4 + 10).
void main() {
  test('GUARD: contact terdaftar sebagai KARTU di private & room', () {
    final priv = File(
      'lib/widgets/private_chat_message.dart',
    ).readAsStringSync();
    final isMedia = RegExp(
      r'final isMediaCard =[\s\S]{0,900}?;',
    ).firstMatch(priv)?.group(0);
    expect(isMedia, isNotNull);
    expect(
      isMedia!.contains("msg.type == 'contact'"),
      isTrue,
      reason: 'contact harus ada di isMediaCard (padding bubble 4)',
    );

    final room = File(
      'lib/screens/room_chat/widgets/room_message_bubble.dart',
    ).readAsStringSync();
    final roomMedia = RegExp(
      r'bool get _isMedia =>[\s\S]{0,900}?;',
    ).firstMatch(room)?.group(0);
    expect(roomMedia, isNotNull);
    expect(
      roomMedia!.contains("msg.type == 'contact'"),
      isTrue,
      reason: 'contact harus ada di _isMedia (room)',
    );
  });

  test('GUARD: ContactBubble ikut aturan kartu (lebar, jam, tombol)', () {
    final src = File('lib/widgets/contact_bubble.dart').readAsStringSync();
    expect(src.contains('chatMediaWidth('), isTrue);
    expect(src.contains('EdgeInsets.fromLTRB(0, 3, 4, 1)'), isTrue);
    // Aksi WAJIB Row+Expanded (lebar sama), bukan Wrap.
    expect(src.contains('Wrap('), isFalse);
  });
}
