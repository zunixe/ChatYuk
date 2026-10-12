/// Hitung cap `imageCache` Flutter dari RAM fisik device — ADAPTIF.
///
/// Terinspirasi Telegram (`ImageLoader.java`): cap cache = `min(maxSize,
/// memoryClass/7)`, yaitu **dinamis** mengikuti RAM device. ChatYuk sebelumnya
/// pakai cap STATIS 40MB di SEMUA device → HP RAM kecil (2–3GB) bisa tertekan
/// (bitmap + Dart heap + native arena) → risiko OOM/jank; HP besar justru
/// kekurangan cache → re-decode lebih sering.
///
/// Formula ChatYuk (konservatif, mendekati memoryClass/7 Android):
///   cap_bytes = clamp(RAM_total / 8, 16MB, 48MB)
///   cap_entri = clamp(RAM_total / 32MB, 60, 160)
///
/// Angka di bawah mengikuti kelas RAM umum Android:
///   2 GB → 16MB / 60 entri   (HP kecil, ketat)
///   3 GB → 24MB / 90 entri
///   4 GB → 32MB / 120 entri  (default sekarang)
///   6 GB → 48MB / 160 entri  (HP besar, cache lebih dalam)
///
/// Murni (tanpa plugin) supaya bisa di-unit-test; pemanggil menyuapkan RAM dari
/// `DeviceInfoPlugin` (di main.dart) atau fallback default bila gagal baca.
library;

/// RAM total default bila deteksi gagal (4GB — samakan perilaku lama).
const int kImageCacheFallbackRamBytes = 4 * 1024 * 1024 * 1024;

/// Batas bawah/atas cap byte (16MB … 48MB).
const int kImageCacheMinBytes = 16 * 1024 * 1024;
const int kImageCacheMaxBytes = 48 * 1024 * 1024;

/// Batas bawah/atas jumlah entri (60 … 160).
const int kImageCacheMinEntries = 60;
const int kImageCacheMaxEntries = 160;

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Cap byte imageCache untuk [ramBytes] RAM fisik.
///
/// Proporsional (RAM/32) sehingga berbeda nyata per kelas RAM, lalu di-clamp:
///   2GB → 64MB→clamp 16MB
///   3GB → 96→clamp 24MB… (lihat tabel: pakai RAM/128 agar mendekati kelas)
int imageCacheBytesForRam(int ramBytes) {
  if (ramBytes <= 0) ramBytes = kImageCacheFallbackRamBytes;
  // RAM/128: 2GB→16MB, 3GB→24MB, 4GB→32MB, 6GB→48MB. Di-clamp ke [16,48].
  return _clamp(ramBytes ~/ 128, kImageCacheMinBytes, kImageCacheMaxBytes);
}

/// Cap jumlah entri imageCache untuk [ramBytes] RAM fisik.
/// RAM/32MB: 2GB→64, 3GB→96, 4GB→128, 6GB→192→clamp 160.
int imageCacheEntriesForRam(int ramBytes) {
  if (ramBytes <= 0) ramBytes = kImageCacheFallbackRamBytes;
  const mib = 32 * 1024 * 1024;
  return _clamp(ramBytes ~/ mib, kImageCacheMinEntries, kImageCacheMaxEntries);
}
