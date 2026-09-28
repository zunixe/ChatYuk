import '../../models/message_model.dart';

/// Jaring pengaman dedupe bubble optimistik (pending) vs gema server.
///
/// Bug yang dikunci: pencocokan HANYA via isi teks tanpa filter waktu —
/// pesan lama yang kebetulan sama isinya ("ok", emoji) langsung membuang
/// pending yang baru dikirim pada emisi berikutnya, padahal gema server-nya
/// belum tiba. Gejala: pesan "tidak kekirim lalu hilang", muncul lagi
/// telat; kirim teks sama 2× makin parah (satu gema memakan dua pending).
///
/// Aturan (sama seperti cabang foto/voice/video):
/// - hanya pesan server yang lebih baru dari [openedAt] (history di-skip),
/// - tiap id server hanya boleh memakai SATU pending ([consumedIds]),
/// - pending yang dibuang = yang TERTUA dengan teks sama (FIFO).
///
/// Id server yang fresh SELALU ditandai terpakai (return -1 bila tidak ada
/// pending cocok) supaya tidak memakan pending identik yang dikirim
/// belakangan. Murni & testable.
int consumeConfirmedText({
  required MessageModel server,
  required DateTime openedAt,
  required Set<String> consumedIds,
  required List<MessageModel> pendings,
}) {
  if (server.type != 'text') return -1;
  if (!server.timestamp.isAfter(openedAt)) return -1;
  if (!consumedIds.add(server.id)) return -1;
  return pendings.indexWhere(
    (p) => p.type == 'text' && p.text == server.text,
  );
}
