import 'package:flutter_test/flutter_test.dart';

/// Kontrak `_computeLeftUid` admin_chat_view_screen.dart:
/// 1) participantOrder >=2 → first
/// 2) chatId 'uid1_uid2' → parts.first
/// 3) senders terurut → sorted.first (stabil, bukan urutan kedatangan)
/// 4) gagal semua → null.
/// Cermin murni supaya prioritas terkunci walau widget pump berat.
String? computeLeftUid({
  required List<String> participantOrder,
  required String chatId,
  required List<String> senders,
}) {
  if (participantOrder.length >= 2) return participantOrder.first;
  final parts = chatId.split('_');
  if (parts.length == 2) return parts.first;
  if (senders.isNotEmpty) {
    final sorted = List<String>.of(senders)..sort();
    return sorted.first;
  }
  return null;
}

void main() {
  test('participantOrder menang atas chatId/senders', () {
    expect(
      computeLeftUid(
        participantOrder: ['u-kiri', 'u-kanan'],
        chatId: 'a_b',
        senders: ['z', 'a'],
      ),
      'u-kiri',
    );
  });

  test('chatId 1:1 dipakai bila tanpa participantOrder', () {
    expect(
      computeLeftUid(
          participantOrder: const [], chatId: 'uid1_uid2', senders: const []),
      'uid1',
    );
  });

  test('fallback senders terurut stabil (bukan urutan datang)', () {
    expect(
      computeLeftUid(
        participantOrder: const [],
        chatId: 'tanpa-separator',
        senders: ['u-z', 'u-a', 'u-m'],
      ),
      'u-a',
    );
  });

  test('semua gagal → null (aman, tidak crash)', () {
    expect(
      computeLeftUid(
        participantOrder: const [],
        chatId: 'tanpa-separator',
        senders: const [],
      ),
      isNull,
    );
  });
}
