import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message_model.dart';
import '../utils.dart';

/// Isi `imageData` pesan stiker (path `stickers/...` dari kolom `image_data`).
///
/// Latar: list pesan (private & room) TIDAK menyeleksi `image_data` (base64
/// lama bikin buka chat berat) — foto diisi terpisah via PhotoCache. Stiker
/// menyimpan path-nya justru di `image_data`, jadi tanpa pengisian ini
/// bubble stiker kosong selamanya setelah reload (realtime sempat mengisi
/// → "muncul", reload berikutnya mengosongkan → "ilang").
///
/// Hanya mengisi STRING path (1 query batch per 20 id). Download + cache
/// dilakukan [StickerBubble] sendiri (mem 120 + disk), bukan PhotoCache —
/// stiker kecil & sering dipakai ulang, tak perlu enkripsi/thumbnail foto.
///
/// ANTI-KEDIP: kembalikan `imageData` lama ke baris server yang kosong.
///
/// List pesan tak menyeleksi `image_data`, jadi baris server untuk stiker
/// selalu `imageData=''`. Tanpa ini tiap reload menimpa path yang sudah
/// terisi → bubble blank → isi ulang → "ngedip". Hanya untuk id+type sama
/// (pesan lain tak tersentuh).
List<MessageModel> preserveStickerPaths(
  List<MessageModel> fresh,
  List<MessageModel> old,
) {
  final oldById = {for (final m in old) m.id: m};
  return [
    for (final s in fresh)
      if (s.imageData.isEmpty &&
          oldById[s.id]?.type == s.type &&
          (oldById[s.id]?.imageData.isNotEmpty ?? false))
        s.copyWith(imageData: oldById[s.id]!.imageData)
      else
        s,
  ];
}

/// Idempotent: hanya pesan yang `imageData`-nya masih kosong yang diubah;
/// aman dipanggil berulang (boot mem → cache → server 3×).
///
/// [currentGetter] mengembalikan list pesan TERKINI (bukan snapshot). Saat boot
/// `_current` di-REASSIGN (merge server, lihat chat_stream_session) setelah
/// panggilan async ini dimulai — kalau memakai referensi tetap, pengisian path
/// kena instance lama → hilang → **stiker lama tetap kosong walau baru muncul**.
Future<void> fillStickerPaths({
  required SupabaseClient sb,
  required String table,
  required List<MessageModel> stickers,
  required List<MessageModel> Function() currentGetter,
  required bool Function() isClosed,
  required void Function() emit,
  required void Function() scheduleCacheSave,
}) async {
  try {
    for (var i = 0; i < stickers.length; i += 20) {
      if (isClosed()) return;
      final batch = stickers.skip(i).take(20).toList();
      final rows = await sb
          .from(table)
          .select('id,image_data')
          .inFilter('id', [for (final m in batch) m.id]);
      if (isClosed()) return;
      var changed = false;
      // Ambil list TERKINI tiap batch (bisa sudah berbeda dari saat panggil).
      final current = currentGetter();
      for (final r in rows) {
        final path = (r['image_data'] as String? ?? '');
        if (path.isEmpty) continue;
        final idx = current.indexWhere((x) => x.id == '${r['id']}');
        if (idx >= 0 && current[idx].imageData.isEmpty) {
          current[idx] = current[idx].copyWith(imageData: path);
          changed = true;
        }
      }
      if (changed) {
        emit();
        scheduleCacheSave();
      }
    }
  } catch (e) {
    dlog('[sticker fill] error: $e');
  }
}
