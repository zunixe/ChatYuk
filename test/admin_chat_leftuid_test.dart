import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/screens/admin_chat_view_screen.dart'
    show computeMonitorLeftUid;

/// Kontrak `computeMonitorLeftUid` (dipakai `_computeLeftUid` State):
/// 1) participantOrder >=2 → first
/// 2) chatId 'uid1_uid2' → parts.first
/// 3) senders terurut → sorted.first (stabil, bukan urutan kedatangan)
/// 4) gagal semua → null.
/// Menguji FUNGSI ASLI (bukan cermin) supaya refactor prod memerahkan test.
void main() {
  test('participantOrder menang atas chatId/senders', () {
    expect(
      computeMonitorLeftUid(
        participantOrder: ['u-kiri', 'u-kanan'],
        chatId: 'a_b',
        senders: ['z', 'a'],
      ),
      'u-kiri',
    );
  });

  test('chatId 1:1 dipakai bila tanpa participantOrder', () {
    expect(
      computeMonitorLeftUid(
          participantOrder: const [], chatId: 'uid1_uid2', senders: const []),
      'uid1',
    );
  });

  test('fallback senders terurut stabil (bukan urutan datang)', () {
    expect(
      computeMonitorLeftUid(
        participantOrder: const [],
        chatId: 'tanpa-separator',
        senders: ['u-z', 'u-a', 'u-m'],
      ),
      'u-a',
    );
  });

  test('semua gagal → null (aman, tidak crash)', () {
    expect(
      computeMonitorLeftUid(
        participantOrder: const [],
        chatId: 'tanpa-separator',
        senders: const [],
      ),
      isNull,
    );
  });
}
