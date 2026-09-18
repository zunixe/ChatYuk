import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils.dart';

/// Alat ukur performa (HANYA aktif saat `--dart-define=PERF_PROBE=true`).
///
/// Tujuan: punya angka sebelum/sesudah optimasi — waktu tap tab → frame
/// pertama tab ter-render, jumlah build per layar, dan jumlah
/// notifyListeners per provider. Saat probe off, semua method jadi
/// no-op (tanpa Stopwatch, tanpa map entry) supaya nol overhead di rilis.
///
/// Pakai: `flutter run --dart-define=PERF_PROBE=true`, lalu
/// `adb logcat | grep '[PERF]'`.
class PerfProbe {
  PerfProbe._();

  /// Nyalakan dari build: `--dart-define=PERF_PROBE=true`.
  static const bool enabled =
      bool.fromEnvironment('PERF_PROBE') && (kDebugMode || kProfileMode);

  // ── Tap tab → frame pertama ──
  static final Map<int, Stopwatch> _tabWatch = {};
  static final Map<int, List<int>> _tabFramesUs = {};

  // ── Hitungan build per layar ──
  static final Map<String, int> _buildCounts = {};

  // ── Hitungan notify per provider ──
  static final Map<String, int> _notifyCounts = {};

  /// Tandai mulai pindah ke tab [index] (dipanggil saat tap nav).
  static void tabStart(int index) {
    if (!enabled) return;
    _tabWatch[index] = Stopwatch()..start();
  }

  /// Tandai tab [index] sudah ter-render di layar (panggil dari
  /// addPostFrameCallback setelah IndexedStack berganti index).
  static void tabEnd(int index) {
    if (!enabled) return;
    final w = _tabWatch[index];
    if (w == null) return;
    w.stop();
    _tabWatch.remove(index);
    final us = w.elapsedMicroseconds;
    (_tabFramesUs[index] ??= []).add(us);
    final list = _tabFramesUs[index]!;
    dlog('[PERF] tab$index tap→frame ${(us / 1000).toStringAsFixed(1)}ms '
        '(n=${list.length}, avg=${(_avg(list) / 1000).toStringAsFixed(1)}ms)');
  }

  /// Hitung sekali build untuk layar [key].
  static void buildCount(String key) {
    if (!enabled) return;
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
  static Future<T> timed<T>(String key, Future<T> Function() fn) async {
    if (!enabled) return fn();
    final w = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      w.stop();
      (_fetchUs[key] ??= []).add(w.elapsedMicroseconds);
      final list = _fetchUs[key]!;
      dlog('[PERF] fetch $key ${(w.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms '
          '(n=${list.length}, avg=${(_avg(list) / 1000).toStringAsFixed(1)}ms)');
    }
  }

  /// Ukur blok sinkron (mis. parse + sort list).
  static T measure<T>(String key, T Function() fn) {
    if (!enabled) return fn();
    final w = Stopwatch()..start();
    final r = fn();
    w.stop();
    (_fetchUs[key] ??= []).add(w.elapsedMicroseconds);
    return r;
  }

  /// Reset semua hitungan (untuk membandingkan periode tertentu).
  static void reset() {
    if (!enabled) return;
    _buildCounts.clear();
    _notifyCounts.clear();
    _fetchUs.clear();
  }

  /// Cetak ringkasan + reset hitungan build/notify.
  static void report(String label) {
    if (!enabled) return;
    dlog('[PERF] ── $label ──');
    for (int i = 0; i < 4; i++) {
      final list = _tabFramesUs[i];
      if (list == null || list.isEmpty) continue;
      dlog('[PERF] tab$i avg=${(_avg(list) / 1000).toStringAsFixed(1)}ms '
          'max=${(list.reduce((a, b) => a > b ? a : b) / 1000).toStringAsFixed(1)}ms '
          'n=${list.length}');
    }
    final builds = _buildCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in builds) {
      dlog('[PERF] build ${e.key}=${e.value}');
    }
    final notifies = _notifyCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in notifies) {
      dlog('[PERF] notify ${e.key}=${e.value}');
    }
    final fetches = _fetchUs.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final e in fetches) {
      dlog('[PERF] fetch ${e.key} n=${e.value.length} '
          'avg=${(_avg(e.value) / 1000).toStringAsFixed(1)}ms '
          'max=${(e.value.reduce((a, b) => a > b ? a : b) / 1000).toStringAsFixed(1)}ms');
    }
    reset();
  }

  static double _avg(List<int> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
}
