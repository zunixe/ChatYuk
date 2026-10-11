/// Registry callback trim ADMIN (R6/R7) — agar `didHaveMemoryPressure` bisa
/// membuang cache berat panel admin TANPA memaksa `ref.read(adminProvider)`
/// (yang akan membuat instance walau panel belum pernah dibuka).
///
/// Alur: AdminProvider mendaftarkan `trimMemCache` saat dibuat, melepas saat
/// dispose. app.dart memanggil [run] dari `didHaveMemoryPressure`/background.
/// Semua dibungkus try/catch: trim TIDAK boleh melempar ke pemanggil.
library;

class AdminTrimRegistry {
  AdminTrimRegistry._();

  static final List<void Function()> _trims = [];

  /// Daftarkan (idempoten per fungsi unik).
  static void register(void Function() fn) {
    if (!_trims.contains(fn)) _trims.add(fn);
  }

  static void unregister(void Function() fn) {
    _trims.remove(fn);
  }

  /// Jalankan semua trim terdaftar (no-op bila panel admin belum dibuka).
  static void run() {
    for (final fn in List<void Function()>.of(_trims)) {
      try {
        fn();
      } catch (_) {}
    }
  }

  /// Jumlah trim terdaftar (uji).
  static int get count => _trims.length;
}
