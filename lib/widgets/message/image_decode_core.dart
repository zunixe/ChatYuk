import 'dart:typed_data';

import '../../core/media/image_cache_hygiene.dart';

// Hasil decode: bytes + dimensi asli agar tampilan proporsional.
class DecodedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  const DecodedImage(this.bytes, this.width, this.height);
}

// Cache decode agar scroll-back tidak resize (glitch). Key = hash imageData,
// bounded 40 (LRU) cegah OOM. 40 (dulu 80) supaya RAM di HP 4-6GB lebih lega
// (tiap entri foto menyimpan bytes asli; video poster terpisah di disk cache).
final decodedImageCache = <int, DecodedImage>{};
// PERF: 40 → 16. Tiap entri = bytes foto asli (bisa ~2-3MB). 40 entri bisa
// menahan ~80-120MB → GC storm seiring pemakaian. 16 cukup untuk bubble yang
// tampil sekaligus saat scroll; foto lain dibaca ulang dari cache disk/chat.
const _decodedCacheMax = 12;
// Daftarkan pembersih ke hygiene logout (satu titik, lihat
// core/media/image_cache_hygiene.dart) — bytes foto user lama tidak boleh
// tinggal di RAM setelah ganti akun. Lazy: dipanggil saat cache pertama diisi.
bool _hygieneRegistered = false;
void _putDecodedCache(int key, DecodedImage img) {
  if (!_hygieneRegistered) {
    _hygieneRegistered = true;
    ImageCacheHygiene.registerAppCache(decodedImageCache.clear);
  }
  if (decodedImageCache.length >= _decodedCacheMax) {
    decodedImageCache.remove(decodedImageCache.keys.first);
  }
  decodedImageCache[key] = img;
}

/// Simpan [img] ke cache decode dengan kunci [key] (bounded LRU).
void putDecodedCache(int key, DecodedImage img) => _putDecodedCache(key, img);

// Daftarkan hasil decode milik [base64] agar path storage yang isinya SAMA
// langsung hit cache — pengirim tidak perlu download ulang fotonya sendiri
// saat versi server tiba via stream (anti kedip kotak → foto). Dipanggil
// setelah upload berhasil, sebelum pesan server masuk. Murni (map) & testable.
void warmPhotoCacheForPath(String path, String base64) {
  if (path.isEmpty || base64.isEmpty) return;
  final cached = decodedImageCache[base64.hashCode];
  if (cached != null) _putDecodedCache(path.hashCode, cached);
}
