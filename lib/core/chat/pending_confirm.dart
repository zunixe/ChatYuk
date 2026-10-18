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

/// Dedupe bubble FILE pending vs gema server: id server sekali pakai,
/// hanya pesan setelah [openedAt], pending dicocokkan via nama file (FIFO).
/// Return index pending yang dibuang atau -1.
int consumeConfirmedFile({
  required MessageModel server,
  required DateTime openedAt,
  required Set<String> consumedIds,
  required List<MessageModel> pendings,
}) {
  if (server.type != 'file') return -1;
  if (!server.timestamp.isAfter(openedAt)) return -1;
  if (!consumedIds.add(server.id)) return -1;
  return pendings.indexWhere(
    (p) => p.type == 'file' && p.text == server.text,
  );
}

/// Dedupe bubble POLL pending vs gema server: sama seperti file, dicocokkan
/// via teks pesan (`📊 <pertanyaan>`), id server sekali pakai, FIFO.
int consumeConfirmedPoll({
  required MessageModel server,
  required DateTime openedAt,
  required Set<String> consumedIds,
  required List<MessageModel> pendings,
}) {
  if (server.type != 'poll') return -1;
  if (!server.timestamp.isAfter(openedAt)) return -1;
  if (!consumedIds.add(server.id)) return -1;
  return pendings.indexWhere(
    (p) => p.type == 'poll' && p.text == server.text,
  );
}

/// Dedupe bubble KONTAK pending vs gema server (teks '📇 <nama>'), id server
/// sekali pakai, FIFO — sama seperti poll/file.
int consumeConfirmedContact({
  required MessageModel server,
  required DateTime openedAt,
  required Set<String> consumedIds,
  required List<MessageModel> pendings,
}) {
  if (server.type != 'contact') return -1;
  if (!server.timestamp.isAfter(openedAt)) return -1;
  if (!consumedIds.add(server.id)) return -1;
  return pendings.indexWhere(
    (p) => p.type == 'contact' && p.text == server.text,
  );
}

/// Dedupe bubble STIKER pending vs gema server. Pending stiker baru berisi
/// base64 (server = path) → cocokkan path persis bila ada, selain itu FIFO
/// per tipe. Id server sekali pakai, hanya pesan setelah [openedAt].
int consumeConfirmedSticker({
  required MessageModel server,
  required DateTime openedAt,
  required Set<String> consumedIds,
  required List<MessageModel> pendings,
}) {
  if (server.type != 'sticker') return -1;
  if (!server.timestamp.isAfter(openedAt)) return -1;
  if (!consumedIds.add(server.id)) return -1;
  final exact = pendings.indexWhere(
    (p) => p.type == 'sticker' && p.imageData == server.imageData,
  );
  if (exact != -1) return exact;
  return pendings.indexWhere((p) => p.type == 'sticker');
}
