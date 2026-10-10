import '../core/nav_guard.dart';

/// 3) senders terurut — supaya tidak semua kanan (null) bila dua sumber
///    di atas gagal.
///
/// Dulu participantOrder menang; itu yang membuat `order.first`
/// bergantung urutan key `participant_names` (JSONB) — ikut berubah saat
/// nickname berubah / beda antara snapshot cache & fetch baru → SEMUA
/// bubble lawan pindah ke kanan. chatId deterministik, jadi sekarang jadi
/// jangkar utama.
String? computeMonitorLeftUid({
  required List<String> participantOrder,
  required String chatId,
  required List<String> senders,
}) {
  final parts = chatId.split('_').where((e) => e.isNotEmpty).toList();
  if (parts.length == 2) return parts.first;
  final order = participantOrder.where((e) => e.isNotEmpty).toList();
  if (order.length >= 2) return order.first;
  if (senders.isNotEmpty) {
    final sorted = senders.where((e) => e.isNotEmpty).toList()..sort();
    if (sorted.isNotEmpty) return sorted.first;
  }
  return null;
}

/// Urutan uid peserta yang DETERMINISTIK dari chatId (uid SORTED, sama
/// dengan `privateChatId`). Dipakai agar label judul + avatar header +
/// sisi bubble admin selalu konsisten & tidak pernah bergeser. Bila
/// chatId tidak berformat 1:1 → urutkan uid unik agar tetap stabil.
List<String> stableChatParticipantOrder({
  required String chatId,
  required List<String> participants,
}) {
  final parts = chatId.split('_').where((e) => e.isNotEmpty).toList();
  if (parts.length == 2) return parts;
  final uniq = <String>{};
  for (final p in participants) {
    if (p.isNotEmpty) uniq.add(p);
  }
  return uniq.toList()..sort();
}

/// Guard anti double-push kartu monitor chat (diuji
/// `test/admin_chat_back_button_test.dart`).
///
/// Tap 2× cepat saat transisi push belum selesai menumpuk 2 route chat
/// identik — 1× back lalu terlihat "tidak ada reaksi" (kasus nyata chat
/// "Anggi & Jaky"). Klaim dilepas saat route di-pop ([releaseChatPush]).
///
/// Implementasi DIPINDAH ke `lib/core/nav_guard.dart` supaya jalur user &
/// admin memakai satu sumber yang sama. Nama lama dipertahankan sebagai
/// pembungkus agar pemanggil + test lama tidak berubah.
bool tryClaimChatPush(String chatId, {DateTime? now}) =>
    tryClaimNav(navKeyChat(chatId), now: now);

/// Lepas klaim [tryClaimChatPush] — dipanggil saat route chat di-pop.
void releaseChatPush(String chatId) => releaseNav(navKeyChat(chatId));

