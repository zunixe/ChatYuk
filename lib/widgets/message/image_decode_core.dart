import 'dart:typed_data';

import '../../core/media/image_cache_hygiene.dart';

// Hasil decode: bytes + dimensi asli agar tampilan proporsional.
class DecodedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  const DecodedImage(this.bytes, this.width, this.height);
}

// Cache decode agar scroll-back tidak resize (glitch). Key = hash imageData.
// P2c (2026-10-11): cap 12 → 32 + **LRU sejati** (dulu FIFO → foto yang MASIH
// tampil bisa terbuang, sementara yang sudah off-screen tetap → re-decode =
// kedip saat scroll chat foto-padat). 32 entri dianggap cukup untuk bubble
// yang tampil sekaligus; tiap entri = bytes foto asli (bounded RAM).
final decodedImageCache = <int, DecodedImage>{};
const _decodedCacheMax = 32;
// Daftarkan pembersih ke hygiene logout (satu titik, lihat
// core/media/image_cache_hygiene.dart) — bytes foto user lama tidak boleh
// tinggal di RAM setelah ganti akun. Lazy: dipanggil saat cache pertama diisi.
bool _hygieneRegistered = false;
void _putDecodedCache(int key, DecodedImage img) {
  if (!_hygieneRegistered) {
    _hygieneRegistered = true;
    ImageCacheHygiene.registerAppCache(decodedImageCache.clear);
  }
  // LRU: hapus dulu (kalau ada) lalu masukkan ulang → posisi jadi "terbaru".
  decodedImageCache.remove(key);
  while (decodedImageCache.length >= _decodedCacheMax) {
    decodedImageCache.remove(decodedImageCache.keys.first);
  }
  decodedImageCache[key] = img;
}

/// Baca dari cache decode + REFRESH LRU (pindah ke posisi terbaru). Dipakai
/// pengganti `decodedImageCache[key]` langsung agar item yang sering dipakai
/// tak terbuang (LRU sejati).
DecodedImage? getDecodedCache(int key) {
  final v = decodedImageCache.remove(key);
  if (v != null) decodedImageCache[key] = v; // re-insert = most-recent
  return v;
}

/// Simpan [img] ke cache decode dengan kunci [key] (bounded LRU).
void putDecodedCache(int key, DecodedImage img) => _putDecodedCache(key, img);

// Daftarkan hasil decode milik [base64] agar path storage yang isinya SAMA
// langsung hit cache — pengirim tidak perlu download ulang fotonya sendiri
// saat versi server tiba via stream (anti kedip kotak → foto). Dipanggil
// setelah upload berhasil, sebelum pesan server masuk. Murni (map) & testable.
void warmPhotoCacheForPath(String path, String base64) {
  if (path.isEmpty || base64.isEmpty) return;
  final cached = getDecodedCache(base64.hashCode);
  if (cached != null) _putDecodedCache(path.hashCode, cached);
}
