import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/screens/admin_chat_view_screen.dart'
    show computeMonitorLeftUid, stableChatParticipantOrder;

/// Kontrak `computeMonitorLeftUid` (dipakai `_computeLeftUid` State):
/// 1) chatId 'uid1_uid2' → parts.first (DETERMINISTIK — jangkar utama)
/// 2) participantOrder >=2 → first (cadangan)
/// 3) senders terurut → sorted.first (stabil, bukan urutan kedatangan)
/// 4) gagal semua → null.
///
/// chatId menang atas participantOrder supaya urutan key
/// `participant_names` (JSONB, ikut berubah saat rename) tidak bisa
/// membalik sisi bubble. Menguji FUNGSI ASLI (bukan cermin) supaya
/// refactor prod memerahkan test.
void main() {
  test('chatId 1:1 menang atas participantOrder (anti-flip)', () {
    expect(
      computeMonitorLeftUid(
        participantOrder: ['u-kanan', 'u-kiri'],
        chatId: 'u-kiri_u-kanan',
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

  test('participantOrder dipakai bila chatId bukan 1:1', () {
    expect(
      computeMonitorLeftUid(
        participantOrder: const ['u-kiri', 'u-kanan'],
        chatId: 'tanpa-separator',
        senders: const [],
      ),
      'u-kiri',
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

  group('stableChatParticipantOrder', () {
    test('1:1 → uid chatId berurutan (abadi)', () {
      expect(
        stableChatParticipantOrder(
          chatId: 'u-b_u-a',
          participants: ['u-a', 'u-b'],
        ),
        ['u-b', 'u-a'],
      );
      expect(
        stableChatParticipantOrder(
          chatId: 'aaa_zzz',
          participants: ['zzz', 'aaa'],
        ),
        ['aaa', 'zzz'],
      );
    });

    test('bukan 1:1 → uid unik terurut', () {
      expect(
        stableChatParticipantOrder(
          chatId: 'tanpa-separator',
          participants: ['z', 'a', 'a', ''],
        ),
        ['a', 'z'],
      );
    });
  });
}
