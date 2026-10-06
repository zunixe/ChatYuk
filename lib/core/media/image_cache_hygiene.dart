import 'package:flutter/painting.dart';

/// Hygiene cache gambar saat logout / ganti akun.
///
/// Foto & avatar milik user lama TIDAK boleh tinggal di RAM setelah logout
/// (HP bergantian pemakai). Fungsi ini mengosongkan:
///  - Flutter `ImageCache` (bitmap hasil decode)
///  - cache aplikasi yang mendaftar lewat [registerAppCache]
///
/// Dipanggil dari `AuthNotifier.signOut()` dan setelah login Google
/// (pola yang sama dengan `MessageCache.clearAllLegacy`).
class ImageCacheHygiene {
  ImageCacheHygiene._();

  static final List<void Function()> _appCaches = [];

  /// Daftarkan pembersih cache aplikasi (mis. `decodedImageCache` chat).
  /// Dipanggil di file pemilik cache (deklarasi top-level), jadi urutan
  /// import menjamin registrasi sebelum logout bisa terjadi.
  static void registerAppCache(void Function() clear) {
    if (!_appCaches.contains(clear)) _appCaches.add(clear);
  }

  /// Kosongkan semua cache gambar. Aman dipanggil kapan pun.
  static void clearAll() {
    try {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    } catch (_) {}
    for (final clear in List<void Function()>.of(_appCaches)) {
      try {
        clear();
      } catch (_) {}
    }
  }
}
