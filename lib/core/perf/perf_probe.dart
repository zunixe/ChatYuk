import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../utils.dart';

/// Alat ukur performa (HANYA aktif saat `--dart-define=PERF_PROBE=true`).
///
/// Tujuan: punya angka sebelum/sesudah optimasi — waktu tap tab → frame
/// pertama tab ter-render, jumlah build per layar, dan jumlah
/// notifyListeners per provider. Saat probe off, semua method jadi
/// no-op (tanpa Stopwatch, tanpa map entry) supaya nol overhead di rilis.
///
/// Pakai: `flutter run --dart-define=PERF_PROBE=true`, lalu
/// `adb logcat | grep '[PERF]'`.
///
/// ── DUA MODE (penting) ──
/// Isu lama: probe butuh build debug/profil supaya `dlog` keluar, tapi
/// build debug = debug key → SHA-1-nya tidak terdaftar di OAuth client →
/// Sign-In gagal `DEVELOPER_ERROR`. Itu yang membuat pengukuran jalur data
/// mandek (lihat docs/PERFORMANCE.md bagian 3).
///
/// Solusinya: **pengukuran data boleh jalan di build RILIS.** Yang perlu
/// hanyalah probe tidak di-strip dan hasilnya terlihat di logcat. Karena itu:
/// - `enabled`  → butuh debug/profil (aman: tidak ada biaya di rilis biasa).
/// - `releaseMeasure` → aktif saat rilis + PERF_PROBE, dan output-nya lewat
///   `print` (bukan `dlog` yang di-gate kDebugMode) supaya tetap muncul di
///   `adb logcat` build rilis.
///
/// Jadi: untuk mengukur `chat.listFetch`, `online.rpc`, dll. di HP kerja,
/// build RILIS dengan `--dart-define=PERF_PROBE=true` — Sign-In tetap jalan,
/// angka tetap keluar. Tidak perlu daftar SHA-1 debug lagi.
class PerfProbe {
  PerfProbe._();

  /// Nyalakan dari build: `--dart-define=PERF_PROBE=true`.
  static const bool enabled =
      bool.fromEnvironment('PERF_PROBE') && (kDebugMode || kProfileMode);

  /// Ukur jalur DATA di build rilis (debug key tidak dipakai → Sign-In aman).
  /// Saat rilis tanpa dart-define = false → nol overhead.
  static const bool releaseMeasure =
      bool.fromEnvironment('PERF_PROBE') && !(kDebugMode || kProfileMode);

  /// True bila pengukuran (apa pun modenya) menyala.
  static const bool measuring = enabled || releaseMeasure;

  /// Log hasil ukur — `dlog` di debug/profil, `print` di rilis (dlog
  /// di-gate kDebugMode sehingga hilang di rilis).
  static void _log(String msg) {
    if (releaseMeasure) {
      // ignore: avoid_print
      print(msg);
    } else {
      dlog(msg);
    }
  }

  // ── Tap tab → frame pertama ──
  static final Map<int, Stopwatch> _tabWatch = {};
  static final Map<int, List<int>> _tabFramesUs = {};

  // ── Hitungan build per layar ──
  static final Map<String, int> _buildCounts = {};

  // ── Hitungan notify per provider ──
  static final Map<String, int> _notifyCounts = {};

  /// Tandai mulai pindah ke tab [index] (dipanggil saat tap nav).
  /// Aktif juga di build RILIS + PERF_PROBE (releaseMeasure) supaya
  /// "tap tab → frame pertama" bisa diukur di HP kerja tanpa build debug.
  static void tabStart(int index) {
    if (!measuring) return;
    _tabWatch[index] = Stopwatch()..start();
  }

  /// Log sisa waktu tap→frame pada N frame berikutnya (untuk melihat apakah
  /// kerja BERLANJUT setelah frame pertama — indikasi "berat" walau frame
  /// pertama cepat).
  static void tabTrace(int index) {
    if (!measuring) return;
    final w = _tabWatch[index];
    if (w == null) return;
    for (var k = 0; k < 6; k++) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _log('[PERF] tab$index +frame$k ${(w.elapsedMilliseconds)}ms');
      });
    }
  }

  /// Tandai tab [index] sudah ter-render di layar (panggil dari
  /// addPostFrameCallback setelah IndexedStack berganti index).
  static void tabEnd(int index) {
    if (!measuring) return;
    final w = _tabWatch[index];
    if (w == null) return;
    w.stop();
    _tabWatch.remove(index);
    final us = w.elapsedMicroseconds;
    (_tabFramesUs[index] ??= []).add(us);
    final list = _tabFramesUs[index]!;
    _log('[PERF] tab$index tap→frame ${(us / 1000).toStringAsFixed(1)}ms '
        '(n=${list.length}, avg=${(_avg(list) / 1000).toStringAsFixed(1)}ms)');
  }

  /// Hitung sekali build untuk layar [key].
  /// Aktif juga di build RILIS + PERF_PROBE (releaseMeasure) supaya jumlah
  /// rebuild layar call bisa dibandingkan sebelum/sesudah di HP kerja.
  static void buildCount(String key) {
    if (!measuring) return;
    _buildCounts[key] = (_buildCounts[key] ?? 0) + 1;
  }

  /// Hitung sekali notifyListeners untuk provider [key].
  static void notifyCount(String key) {
    if (!enabled) return;
    _notifyCounts[key] = (_notifyCounts[key] ?? 0) + 1;
  }

  /// Ambil jumlah build layar [key] sejak probe mulai.
  static int buildsOf(String key) => _buildCounts[key] ?? 0;

  /// Ambil jumlah notify provider [key] sejak probe mulai.
  static int notifiesOf(String key) => _notifyCounts[key] ?? 0;

  // ── Waktu fetch per jalur data (bukan render) ──
  // Inilah tersangka utama sisa kelambatan setelah render terbukti mulus.
  static final Map<String, List<int>> _fetchUs = {};

  /// Ukur satu operasi async: `await PerfProbe.timed('chat.fetch', () => ...)`.
  /// Aktif juga di build rilis (lihat [releaseMeasure]) supaya jalur data
  /// bisa diukur di HP kerja tanpa merusak Sign-In.
  static Future<T> timed<T>(String key, Future<T> Function() fn) async {
    if (!measuring) return fn();
    final w = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      w.stop();
      (_fetchUs[key] ??= []).add(w.elapsedMicroseconds);
      final list = _fetchUs[key]!;
      _log('[PERF] fetch $key ${(w.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms '
          '(n=${list.length}, avg=${(_avg(list) / 1000).toStringAsFixed(1)}ms)');
    }
  }

  /// Ukur blok sinkron (mis. parse + sort list).
  static T measure<T>(String key, T Function() fn) {
    if (!measuring) return fn();
    final w = Stopwatch()..start();
    final r = fn();
    w.stop();
    (_fetchUs[key] ??= []).add(w.elapsedMicroseconds);
    return r;
  }

  /// Catat satu durasi yang sudah diukur manual (ms) — dipakai jalur yang
  /// tidak bisa dibungkus `timed` (mis. call init → fase inCall, offer →
  /// answer) supaya ikut muncul di `report()`.
  static void record(String key, Duration d) {
    if (!measuring) return;
    (_fetchUs[key] ??= []).add(d.inMicroseconds);
  }

  // ── Waktu frame nyata (build + raster) — deteksi jank saat pindah tab ──
  static final List<int> _frameBuildUs = [];
  static final List<int> _frameRasterUs = [];
  static bool _timingsHooked = false;

  /// Pasang hook timing frame (panggil sekali saat app start bila measuring).
  /// Mengukur `buildDuration` (UI/CPU) & `rasterDuration` (GPU) tiap frame —
  /// inilah "rasa berat" sebenarnya, bukan sekadar tap→frame pertama.
  static void hookFrameTimings() {
    if (!measuring || _timingsHooked) return;
    _timingsHooked = true;
    try {
      SchedulerBinding.instance.addTimingsCallback((timings) {
        for (final t in timings) {
          _frameBuildUs.add(t.buildDuration.inMicroseconds);
          _frameRasterUs.add(t.rasterDuration.inMicroseconds);
          if (_frameBuildUs.length > 4000) _frameBuildUs.removeAt(0);
          if (_frameRasterUs.length > 4000) _frameRasterUs.removeAt(0);
        }
      });
    } catch (_) {}
  }

  /// Ringkasan jank frame sejak reset terakhir.
  static String frameSummary() {
    if (_frameBuildUs.isEmpty && _frameRasterUs.isEmpty) return 'no-frames';
    final b = List<int>.of(_frameBuildUs)..sort();
    final r = List<int>.of(_frameRasterUs)..sort();
    int janky = 0;
    for (final v in _frameBuildUs) {
      if (v > 16000) janky++;
    }
    int jankyR = 0;
    for (final v in _frameRasterUs) {
      if (v > 16000) jankyR++;
    }
    return 'frames=${_frameBuildUs.length} '
        'build[p50=${(_pct(b, 50) / 1000).toStringAsFixed(1)} '
        'p90=${(_pct(b, 90) / 1000).toStringAsFixed(1)} '
        'max=${(b.last / 1000).toStringAsFixed(1)}ms] '
        'raster[p50=${(_pct(r, 50) / 1000).toStringAsFixed(1)} '
        'p90=${(_pct(r, 90) / 1000).toStringAsFixed(1)} '
        'max=${(r.last / 1000).toStringAsFixed(1)}ms] '
        'janky(build)=$janky janky(raster)=$jankyR';
  }

  /// Reset semua hitungan (untuk membandingkan periode tertentu).
  static void reset() {
    if (!measuring) return;
    _buildCounts.clear();
    _notifyCounts.clear();
    _fetchUs.clear();
    _frameBuildUs.clear();
    _frameRasterUs.clear();
  }

  /// Cetak ringkasan + reset hitungan build/notify.
  static void report(String label) {
    if (!measuring) return;
    _log('[PERF] ── $label ──');
    _log('[PERF] ${frameSummary()}');
    for (int i = 0; i < 4; i++) {
      final list = _tabFramesUs[i];
      if (list == null || list.isEmpty) continue;
      _log('[PERF] tab$i avg=${(_avg(list) / 1000).toStringAsFixed(1)}ms '
          'max=${(list.reduce((a, b) => a > b ? a : b) / 1000).toStringAsFixed(1)}ms '
          'n=${list.length}');
    }
    final builds = _buildCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in builds) {
      _log('[PERF] build ${e.key}=${e.value}');
    }
    final notifies = _notifyCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in notifies) {
      _log('[PERF] notify ${e.key}=${e.value}');
    }
    final fetches = _fetchUs.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final e in fetches) {
      final v = List<int>.of(e.value)..sort();
      _log('[PERF] fetch ${e.key} n=${v.length} '
          'avg=${(_avg(v) / 1000).toStringAsFixed(1)}ms '
          'min=${(v.first / 1000).toStringAsFixed(1)}ms '
          'p50=${(_pct(v, 50) / 1000).toStringAsFixed(1)}ms '
          'p90=${(_pct(v, 90) / 1000).toStringAsFixed(1)}ms '
          'max=${(v.last / 1000).toStringAsFixed(1)}ms');
    }
    reset();
  }

  static double _avg(List<int> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  /// Rata-rata (0 bila kosong) — diekspos untuk test statistik probe.
  @visibleForTesting
  static double avgOf(List<int> v) => _avg(v);

  /// Persentil dari daftar yang SUDAH terurut (interpolasi linear).
  /// Dipakai membedakan noise (max jauh dari p50) dari pola (p90 ikut naik).
  static double _pct(List<int> sorted, int p) {
    if (sorted.isEmpty) return 0;
    if (sorted.length == 1) return sorted.first.toDouble();
    final rank = (p / 100) * (sorted.length - 1);
    final lo = rank.floor();
    final hi = rank.ceil();
    if (lo == hi) return sorted[lo].toDouble();
    final frac = rank - lo;
    return sorted[lo] * (1 - frac) + sorted[hi] * frac;
  }

  /// Persentil dari daftar SUDAH terurut (interpolasi linear) — diekspos
  /// untuk test (p50/p90 sering salah kalau rank tidak di-handle benar).
  @visibleForTesting
  static double pctOf(List<int> sorted, int p) => _pct(sorted, p);
}
