/// Toggle A/B/C untuk pengukuran terkontrol (default AKTIF).
///
/// `--dart-define=PERF_ABC_OFF=true` → mematikan optimasi A/B/C sehingga build
/// yang SAMA bisa diukur "sebelum" (baseline) vs "sesudah", tanpa mengubah kode
/// atau menyimpan dua branch. Dipakai HANYA saat profiling.
library;

/// True bila A/B/C DIMATIKAN (baseline lama).
const bool kPerfAbcOff = bool.fromEnvironment('PERF_ABC_OFF');

/// A = cap imageCache adaptif RAM. B = cache avatar terpisah. C = RGB_565+pool.
bool get abcAEnabled => !kPerfAbcOff;
bool get abcBEnabled => !kPerfAbcOff;
bool get abcCEnabled => !kPerfAbcOff;
