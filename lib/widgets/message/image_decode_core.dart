import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/media/image_cache_hygiene.dart';

// Hasil decode: bytes + dimensi asli agar tampilan proporsional.
/// [image]: bitmap SIAP-RENDER (`ui.Image`) — kalau ada, bubble render via
/// `RawImage` = **nol decode** (contek video). Kalau null, fallback
/// `Image.memory(bytes)` (decode saat render). Diisi oleh [attachDecodedImage].
class DecodedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  ui.Image? image;

  /// True setelah [safeDispose] dijalankan — bitmap GPU sudah dilepas.
  /// RENDER WAJIB cek ini: memakai `image` yang sudah di-dispose = crash
  /// "Cannot draw a disposed image". Bila true, jatuh ke `Image.memory(bytes)`.
  bool disposed = false;

  DecodedImage(this.bytes, this.width, this.height, [this.image]);

  /// Lepas bitmap GPU (`ui.Image`) dengan AMAN & idempoten.
  ///
  /// Guard berlapis (R10): (1) idempoten via [disposed]; (2) `image` di-null-kan
  /// SEBELUM dispose agar render berikutnya tak menyentuh handle mati;
  /// (3) try/catch — dispose ganda / race TIDAK boleh melempar ke UI.
  void safeDispose() {
    if (disposed) return;
    disposed = true;
    final img = image;
    image = null;
    try {
      img?.dispose();
    } catch (_) {}
  }
}

/// Decode [bytes] → `ui.Image` (target lebar) lalu pasang ke [di]. Menjadikan
/// render bubble NOL-decode (bitmap sudah siap) — foto secepat video.
///
/// TANPA timeout (timeout = `Timer` yang membuat test widget gagal / bisa
/// menahan). `instantiateImageCodec` dengan bytes JPEG valid tak menggantung;
/// bila gagal, `di.image` tetap null → fallback `Image.memory(bytes)`.
Future<void> attachDecodedImage(DecodedImage di, {int? targetWidth}) async {
  if (di.disposed || di.image != null) return;
  try {
    final codec = await ui.instantiateImageCodec(
      di.bytes,
      targetWidth: targetWidth,
    );
    final frame = await codec.getNextFrame();
    // Race: bisa ter-dispose selama await → jangan pasang handle mati.
    if (di.disposed) {
      try {
        frame.image.dispose();
      } catch (_) {}
      return;
    }
    di.image = frame.image;
  } catch (_) {}
}

// Cache decode agar scroll-back tidak resize (glitch). Key = hash imageData.
// P2c (2026-10-11): cap 12 → 32 + **LRU sejati** (dulu FIFO → foto yang MASIH
// tampil bisa terbuang, sementara yang sudah off-screen tetap → re-decode =
// kedip saat scroll chat foto-padat). 32 entri dianggap cukup untuk bubble
// yang tampil sekaligus; tiap entri = bytes foto asli (bounded RAM).
//
// 2026-10-17 (rekaman HP: tile album KOSONG 1–2 frame saat data server
// masuk): SATU foto disimpan di 3–4 kunci (base64 lokal, path storage,
// `thumb:<id>`, isi data). Cap 32 KUNCI = efektif ~8–10 foto → chat ±27 foto
// terus menggusur `thumb:<id>` → tile yang di-mount ulang MISS → kotak kosong.
// Sekarang dibatasi per FOTO UNIK (objek) — kunci alias tidak menghabiskan
// kuota — plus batas kunci total supaya peta tetap bounded.
final decodedImageCache = <int, DecodedImage>{};
const decodedCacheMaxUnique = 20;
const decodedCacheMaxKeys = 128;

int _uniqueCount() =>
    (Set<DecodedImage>.identity()..addAll(decodedImageCache.values)).length;
// Daftarkan pembersih ke hygiene logout (satu titik, lihat
// core/media/image_cache_hygiene.dart) — bytes foto user lama tidak boleh
// tinggal di RAM setelah ganti akun. Lazy: dipanggil saat cache pertama diisi.
bool _hygieneRegistered = false;
void _putDecodedCache(int key, DecodedImage img) {
  if (!_hygieneRegistered) {
    _hygieneRegistered = true;
    ImageCacheHygiene.registerAppCache(decodedImageCache.clear);
  }
  // LRU: hapus dulu (kalau ada). Bila entri lama untuk kunci SAMA digantikan
  // objek BARU → bitmap lama tak dipakai lagi → lepas (R10). HANYA di jalur
  // replace kunci-sama (aman: tak ada widget lain memegang referensi objek
  // yang baru saja digantikan dari cache). Entri yang dibuang karena evict LRU
  // (keys.first) SENGAJA TIDAK di-dispose — bisa masih dirender widget lain.
  final removed = decodedImageCache.remove(key);
  if (removed != null && !identical(removed, img)) {
    removed.safeDispose();
  }
  decodedImageCache[key] = img;
  while (decodedImageCache.length > decodedCacheMaxKeys ||
      _uniqueCount() > decodedCacheMaxUnique) {
    final first = decodedImageCache.keys.first;
    if (first == key && decodedImageCache.length == 1) break;
    decodedImageCache.remove(first);
  }
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
