import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regresi: tombol "Global Room" di halaman Online harus membuka MENU UTAMA
/// Global Room (tab Chat → section Rooms), BUKAN langsung masuk ke room
/// spesifik "General".
void main() {
  test('GUARD: _openGeneralRoom tidak mem-push RoomChatScreen', () {
    final src = File(
      'lib/screens/online_users_screen.dart',
    ).readAsStringSync();

    final start = src.indexOf('Future<void> _openGeneralRoom(');
    expect(start, greaterThan(-1), reason: '_openGeneralRoom harus ada');
    // Ambil badan fungsi sampai penutupnya.
    var depth = 0;
    var i = src.indexOf('{', start);
    final bodyStart = i;
    for (; i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    final body = src.substring(bodyStart, i);

    expect(body.contains('RoomChatScreen'), isFalse,
        reason: 'jangan push room spesifik — cukup buka daftar Global Room');
    expect(body.contains('Navigator.of('), isFalse,
        reason: 'tidak boleh push rute apa pun');
    // Harus tetap mengalihkan ke tab Chat + section Rooms + kategori general.
    expect(body.contains('requestedChatSection.value = ChatSection.rooms'),
        isTrue);
    expect(body.contains("setExploreCategory('general')"), isTrue);
  });
}
