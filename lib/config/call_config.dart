import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'supabase_config.dart';
import '../core/perf/perf_probe.dart';

/// Konfigurasi ICE untuk WebRTC call.
/// TURN credentials di-fetch dari Supabase Edge Function (Cloudflare TURN).
class CallConfig {
  static const String _turnFunctionUrl =
      'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/turn-credentials';

  static const List<Map<String, dynamic>> _fallbackIceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {
      'urls': [
        'turn:openrelay.metered.ca:80',
        'turn:openrelay.metered.ca:80?transport=tcp',
        'turns:openrelay.metered.ca:443',
        'turns:openrelay.metered.ca:443?transport=tcp',
      ],
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ];

  static const Map<String, dynamic> peerConfig = {
    'iceServers': _fallbackIceServers,
    'sdpSemantics': 'unified-plan',
  };

  /// True bila `getPeerConfig` terakhir benar-benar memaksa relay-only
  /// (Cloudflare tersedia & `relayOnly` diminta). Dipakai `CallSession`
  /// untuk tahu apakah fallback "all candidates" masih berguna saat ICE
  /// gagal — kalau Cloudflare tak tersedia, kandidat host/srflx sudah
  /// dipakai sehingga fallback tak perlu.
  static bool lastConfigWasRelayOnly = false;

  /// Cache kredensial Cloudflare di memori. Cloudflare menerbitkan credential
  /// dengan TTL 24 jam, tapi `_fetchCloudflare` dulu dipanggil SETIAP call dan
  /// SETIAP watch PC → round-trip edge function berulang (terukur 1760ms cold,
  /// 218ms warm). Cache 12 jam (setengah TTL server = margin aman) menghapus
  /// round-trip itu untuk semua call berikutnya di sesi yang sama.
  static Map<String, dynamic>? _cloudflareCache;
  static DateTime? _cloudflareCachedAt;
  static const Duration _cloudflareTtl = Duration(hours: 12);

  @visibleForTesting
  static String? accessTokenOverride;

  @visibleForTesting
  static http.Client? httpClientOverride;

  @visibleForTesting
  static void clearCloudflareCache() {
    _cloudflareCache = null;
    _cloudflareCachedAt = null;
    accessTokenOverride = null;
    httpClientOverride = null;
  }

  /// Fetch Cloudflare TURN credentials, return null kalau gagal.
  /// Kirim ACCESS TOKEN user (JWT) — function hanya melayani user login.
  /// Publishable key ditolak (bukan JWT user). Anon tanpa session → skip
  /// fetch, fallback openrelay (perilaku aman yang sudah ada).
  static Future<Map<String, dynamic>?> _fetchCloudflare() async {
    final cached = _cloudflareCache;
    final cachedAt = _cloudflareCachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cloudflareTtl) {
      return cached;
    }
    try {
      final token =
          accessTokenOverride ??
          SupabaseConfig.client.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) return null;
      final client = httpClientOverride;
      final resp =
          await (client != null
                  ? client.get(
                      Uri.parse(_turnFunctionUrl),
                      headers: {'Authorization': 'Bearer $token'},
                    )
                  : http.get(
                      Uri.parse(_turnFunctionUrl),
                      headers: {'Authorization': 'Bearer $token'},
                    ))
              .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        // Function proxy jawaban Cloudflare apa adanya — kalau key invalid,
        // body berisi {"error": "..."} tanpa iceServers → anggap gagal.
        final iceData = data['iceServers'] as Map<String, dynamic>?;
        if (iceData != null &&
            iceData['urls'] != null &&
            iceData['username'] != null) {
          _cloudflareCache = iceData;
          _cloudflareCachedAt = DateTime.now();
          return iceData;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Return peerConfig dengan Cloudflare TURN (+ backup relay openrelay).
  /// Dua provider relay independen → ICE punya cadangan kalau satu jalur gagal.
  ///
  /// [relayOnly] = true (DEFAULT, perilaku call lama):
  /// Cloudflare OK → iceTransportPolicy 'relay' (HANYA kandidat relay).
  /// Host/srflx tidak pernah connect di NAT berbeda (log: cuma relay
  /// 104.30.x.x yang works), jadi lewati saja negosiasi host/srflx yang
  /// cuma buang waktu & bikin call kadang pending/timeout. Relay-only =
  /// koneksi deterministik & cepat (1-3 detik).
  ///
  /// [relayOnly] = false (dipakai voice stage):
  /// JANGAN paksa relay-only — pakai semua tipe kandidat (host/srflx/relay)
  /// supaya P2P langsung tetap bisa connect di jaringan sama (WiFi/hotspot)
  /// walau TURN bermasalah, sambil tetap menyediakan relay sebagai cadangan.
  /// Ini mencegah "mic hijau tapi bisu" saat relay gagal/tak tersedia.
  ///
  /// Cloudflare GAGAL (401 / key mati) → JANGAN paksa relay-only; pakai
  /// semua tipe kandidat (host/srflx/relay) supaya P2P langsung tetap bisa
  /// connect — minimal di jaringan yang sama (WiFi/hotspot) tanpa TURN.
  static Future<Map<String, dynamic>> getPeerConfig({
    bool relayOnly = true,
  }) async {
    final cloudflare = await PerfProbe.timed(
      'call.turnFetch',
      _fetchCloudflare,
    );
    final iceServers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
    ];
    if (cloudflare != null) {
      iceServers.add({
        'urls': cloudflare['urls'],
        'username': cloudflare['username'],
        'credential': cloudflare['credential'],
      });
    }
    // Backup relay (server berbeda) kalau Cloudflare tidak bisa connect.
    iceServers.add({
      'urls': [
        'turn:openrelay.metered.ca:80',
        'turn:openrelay.metered.ca:443?transport=tcp',
        'turns:openrelay.metered.ca:443',
      ],
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    });
    final forceRelayOnly = relayOnly && cloudflare != null;
    lastConfigWasRelayOnly = forceRelayOnly;
    return {
      'iceServers': iceServers,
      if (forceRelayOnly) 'iceTransportPolicy': 'relay',
      'iceCandidatePoolSize': 2,
      // Negosiasi lebih cepat: 1 transport untuk audio+video (bukan 2×).
      'rtcpMuxPolicy': 'require',
      'bundlePolicy': 'max-bundle',
      'sdpSemantics': 'unified-plan',
    };
  }
}
