import 'dart:convert';
import 'package:http/http.dart' as http;
import 'supabase_config.dart';

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

  /// Fetch Cloudflare TURN credentials, return null kalau gagal.
  /// Kirim ACCESS TOKEN user (JWT) — function hanya melayani user login.
  /// Publishable key ditolak (bukan JWT user). Anon tanpa session → skip
  /// fetch, fallback openrelay (perilaku aman yang sudah ada).
  static Future<Map<String, dynamic>?> _fetchCloudflare() async {
    try {
      final token = SupabaseConfig.client.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) return null;
      final resp = await http
          .get(
            Uri.parse(_turnFunctionUrl),
            headers: {
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        // Function proxy jawaban Cloudflare apa adanya — kalau key invalid,
        // body berisi {"error": "..."} tanpa iceServers → anggap gagal.
        final iceData = data['iceServers'] as Map<String, dynamic>?;
        if (iceData != null &&
            iceData['urls'] != null &&
            iceData['username'] != null) {
          return iceData;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Return peerConfig dengan Cloudflare TURN (+ backup relay openrelay).
  /// Dua provider relay independen → ICE punya cadangan kalau satu jalur gagal.
  ///
  /// Cloudflare OK → iceTransportPolicy 'relay' (HANYA kandidat relay).
  /// Host/srflx tidak pernah connect di NAT berbeda (log: cuma relay
  /// 104.30.x.x yang works), jadi lewati saja negosiasi host/srflx yang
  /// cuma buang waktu & bikin call kadang pending/timeout. Relay-only =
  /// koneksi deterministik & cepat (1-3 detik).
  ///
  /// Cloudflare GAGAL (401 / key mati) → JANGAN paksa relay-only; pakai
  /// semua tipe kandidat (host/srflx/relay) supaya P2P langsung tetap bisa
  /// connect — minimal di jaringan yang sama (WiFi/hotspot) tanpa TURN.
  static Future<Map<String, dynamic>> getPeerConfig() async {
    final cloudflare = await _fetchCloudflare();
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
    return {
      'iceServers': iceServers,
      if (cloudflare != null) 'iceTransportPolicy': 'relay',
      'iceCandidatePoolSize': 2,
      'sdpSemantics': 'unified-plan',
    };
  }
}
