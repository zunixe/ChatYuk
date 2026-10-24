// Tipe & helper murni untuk ChatStreamSession (dipisah dari
// chat_stream_session.dart supaya file sesi tetap di bawah ratchet ukuran).
// Diekspor ulang oleh chat_stream_session.dart — pemanggil tidak berubah.
import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;

import '../models/message_model.dart';

// Concurrency limiter: max N operasi paralel, sisanya antri.
class ChatSemaphore {
  final int max;
  int _count = 0;
  final _waiters = <Completer<void>>[];
  ChatSemaphore(this.max);
  Future<void> acquire() async {
    if (_count < max) {
      _count++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void release() {
    _count--;
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
      _count++;
    }
  }

  Future<T> run<T>(Future<T> Function() fn) async {
    await acquire();
    try {
      return await fn();
    } finally {
      release();
    }
  }
}

// Topik kanal realtime stream pesan (satu chat/room). SATU sumber untuk
// SUBSCRIBER (`ChatStreamSession`) dan PENGIRIM broadcast (mis.
// `view_once_seen` di ChatService) — topik harus PERSIS sama; dulu pengirim
// memakai `private_<chatId>` sementara subscriber di `msg-<cacheKey>-<n>`
// (sufiks percobaan reconnect) → broadcast tidak pernah bertemu (bug
// "foto sekali-lihat tidak kadaluarsa realtime di pengirim", 2026-10-20).
String chatStreamTopic(String cacheKey) => 'msg-$cacheKey';

/// Event broadcast "ada pesan baru dengan id X" (payload `{chat_id, id}`).
/// Isi pesan TIDAK dikirim lewat broadcast (REVIEW_2026-10-24 SEC-01).
const String chatNewMessageSignalEvent = 'new_message_id';

/// Topik broadcast `view_once_seen` untuk satu chat/room.
String viewOnceSeenTopic({required bool isRoom, required String id}) =>
    chatStreamTopic('${isRoom ? 'room' : 'private'}_$id');

// Handle stream chat — expose stream + aksi loadOlder untuk pagination.
class ChatMessageStream {
  final Stream<List<MessageModel>> stream;
  final Future<void> Function() loadOlder;
  final Future<void> Function(String messageId) fetchImage;

  /// Fetch ulang pesan terbaru dari server — jaring pengaman kalau event
  /// Realtime miss (channel drop) supaya bubble pending tidak nyangkut.
  final Future<void> Function() reload;

  /// A1: revisi isi (naik tiap isi pesan berubah) — kunci cache stabil untuk
  /// `_deriveItems` (hindari recompute O(N) tiap emit stream).
  final ValueListenable<int> revision;

  /// Tandai pesan terhapus / batal hapus SEKETIKA di sesi + cache lokal
  /// (tanpa menunggu gema realtime). Dulu: hapus lalu langsung tutup chat →
  /// gema realtime tak sempat → cache tetap berisi pesan → buka lagi,
  /// pesan terhapus SEMPAT MUNCUL lalu hilang (kedip).
  final void Function(String messageId, bool deleted) markDeleted;
  const ChatMessageStream({
    required this.stream,
    required this.loadOlder,
    required this.fetchImage,
    required this.reload,
    required this.revision,
    required this.markDeleted,
  });
}

/// Tanda tangan ISI list pesan untuk memutuskan perlu tulis cache atau tidak.
///
/// Dulu `'jumlah:idTerakhir'` — hapus/edit pesan TIDAK mengubahnya, sehingga
/// status terhapus/teks editan TIDAK PERNAH disimpan ke cache → buka chat
/// lagi menampilkan isi lama dulu (pesan terhapus "sempat muncul"). Sekarang
/// mencakup id + status hapus + edit + teks tiap pesan (O(n), n ≈ ratusan,
/// dipanggil ter-debounce 2s). Murni & testable.
String messageCacheSignature(List<MessageModel> msgs) {
  if (msgs.isEmpty) return '';
  var h = 17;
  for (final m in msgs) {
    h = Object.hash(h, m.id, m.isDeleted, m.edited, m.text, m.imageData.length);
  }
  return '${msgs.length}:${msgs.last.id}:$h';
}
