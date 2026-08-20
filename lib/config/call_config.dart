/// Konfigurasi ICE untuk WebRTC call.
///
/// TODO(zunixe): isi credential TURN Cloudflare dari dashboard
/// https://dash.cloudflare.com (Realtime → TURN) setelah akun dibuat.
/// STUN publik sudah cukup untuk jaringan normal; TURN wajib untuk
/// NAT ketat / jaringan seluler (mayoritas user Indonesia).
class CallConfig {
  static const String turnUrl = 'turn:turn.cloudflare.com:3478';
  static const String turnUsername = 'GANTI_USERNAME';
  static const String turnCredential = 'GANTI_CREDENTIAL';

  static const List<Map<String, dynamic>> iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {
      'urls': [
        CallConfig.turnUrl,
        'turns:turn.cloudflare.com:5349',
        'turn:turn.cloudflare.com:3478?transport=tcp',
      ],
      'username': CallConfig.turnUsername,
      'credential': CallConfig.turnCredential,
    },
  ];

  static const Map<String, dynamic> peerConfig = {
    'iceServers': iceServers,
    'sdpSemantics': 'unified-plan',
  };
}