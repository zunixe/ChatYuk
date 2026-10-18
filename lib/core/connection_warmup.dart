import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Tunggu koneksi Supabase "hangat" sebelum dipakai.
///
/// Kenapa perlu (terukur 2026-10-18, region Supabase = Tokyo):
///   request COLD (DNS + TCP + TLS handshake) = 792ms
///   request WARM (keep-alive)                = 110-140ms
///
/// Setelah HP idle / app di-background cukup lama, koneksi keep-alive ditutup
/// OS. Request PERTAMA sesudahnya membayar ±792ms penuh — inilah "ngelag
/// setelah idle" yang dirasakan user saat membuka daftar chat.
///
/// Solusi: begitu app kembali ke foreground, tembak satu request RINGAN di
/// belakang (`/auth/v1/health` — tanpa tabel, tanpa RLS) supaya handshake
/// selesai LEBIH AWAL. Saat user benar-benar menekan tombol Chat, koneksi
/// sudah hangat dan request data hanya ±110ms.
///
/// Sifat:
///  - fire-and-forget, tidak pernah melempar (gagal = diabaikan),
///  - di-dedupe (tidak menembak berulang saat resume beruntun),
///  - nol biaya bila dipanggil saat app masih foreground & sudah hangat.
class ConnectionWarmup {
  ConnectionWarmup._();

  static final HttpClient _probe = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    // Sama dengan klien utama: pertahankan koneksi hangat 120s.
    ..idleTimeout = const Duration(seconds: 120)
    ..maxConnectionsPerHost = 2;

  static bool _inFlight = false;
  static DateTime? _lastWarmAt;

  /// Anggap koneksi masih hangat bila warm terakhir < jendela ini.
  /// 110s (sedikit di bawah idleTimeout 120s) → tidak menembak sia-sia.
  static const Duration _freshWindow = Duration(seconds: 110);

  /// Benar bila sudah di-warm belum lama ini.
  static bool get isFresh {
    final at = _lastWarmAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < _freshWindow;
  }

  /// Panaskan koneksi ke [url] (mis. `https://<project>.supabase.co`).
  ///
  /// Aman dipanggil berkali-kali: hanya satu probe berjalan pada satu waktu,
  /// dan tidak melakukan apa pun bila koneksi baru saja dihangatkan.
  static void warm(String url) {
    if (_inFlight || isFresh) return;
    _inFlight = true;
    // Jangan tahan frame: probe jalan setelah frame saat ini selesai.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_probeOnce(url));
    });
  }

  static Future<void> _probeOnce(String url) async {
    try {
      final uri = Uri.parse('$url/auth/v1/health');
      final req = await _probe.getUrl(uri);
      req.headers.set('apikey', 'warmup');
      final res = await req.close().timeout(const Duration(seconds: 4));
      // Buang body — kita hanya butuh handshake + respons header.
      await res.drain<void>();
      _lastWarmAt = DateTime.now();
      if (kDebugMode) debugPrint('[WARMUP] koneksi siap (${res.statusCode})');
    } catch (e) {
      // Gagal = tetap jalan lambat seperti sebelumnya; bukan error fatal.
      if (kDebugMode) debugPrint('[WARMUP] gagal: $e');
    } finally {
      _inFlight = false;
    }
  }
}
