import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config/call_config.dart';
import '../config/supabase_config.dart';
import '../core/call/opus_sdp.dart';
import '../utils.dart';

part 'room_voice_service_stage.dart';
part 'room_voice_service_signal.dart';
part 'room_voice_service_peer.dart';

/// Voice stage global room: mesh WebRTC AUDIO-only, max 6 mic nyala,
/// pendengar unlimited.
///
/// Pola disalin dari `room_broadcast_service.dart` (sudah terbukti):
/// speaker = broadcaster audio, listener menjawab offer. Bedanya:
/// - audio-only (jauh lebih ringan dari video),
/// - peran ganda: tiap sesi SELALU listener, opsional naik stage,
/// - speaker baru diumumkan via `v_speak`, listener membalas `v_join`
///   terarah (speaker tidak kenal daftar listener sebelumnya),
/// - signaling via tabel `room_voice_signals`, stage via RPC
///   `room_voice_join/heartbeat/leave/mute` (max-6 + otorisasi di server).
///
/// - Mic default MATI. `startSpeaking()` = naik stage + mic nyala.
/// - `setMuted(true)` = tetap di stage tapi tidak kirim suara.
/// - Admin/owner mute paksa datang sebagai sinyal `v_mute` terarah.
/// Munge SDP via helper Opus yang sama dengan call 1:1. Tidak pernah

/// mengembalikan string kosong (fallback ke input bila helper gagal).

String _munged(Object? raw) {
  final s = raw as String? ?? '';

  final out = applyOpusLowLatencyPrefs(s);

  return out.isEmpty ? s : out;
}

/// Murni & testable: v_bye basi (generasi lebih tua) wajib diabaikan.

@visibleForTesting
bool isStaleBye(int knownSess, int incomingSess) => incomingSess < knownSess;

/// Murni & testable: tentukan key pc tujuan kandidat ICE.

///

/// Prioritas: (1) cocokkan `candPcId` dengan nilai di [pcIds] → key pc itu;

/// (2) fallback hint arah: 'up' (kandidat untuk pc uplink-ku ke `from`) →

/// key `from`; 'down' (kandidat untuk pc downlink-ku dari `from`) →

/// key `dn_$from`; (3) tanpa hint → `from` bila ada di [peerKeys], else

/// `dn_$from`. Mengembalikan key peer (bukan pcId) supaya `_peers[key]`

/// langsung dapat pc-nya.

@visibleForTesting
String resolveCandidateKey({
  required String from,

  required String candPcId,

  required String dir,

  required Map<String, String> pcIds,

  required Set<String> peerKeys,
}) {
  if (candPcId.isNotEmpty) {
    for (final e in pcIds.entries) {
      if (e.value == candPcId) return e.key;
    }
  }

  if (dir == 'up') {
    // Kandidat dari lawan untuk pc uplink-ku (key `from`), tapi bila itu

    // belum ada, simpan ke slot downlink sebagai jaring pengaman.

    return peerKeys.contains(from) ? from : 'dn_$from';
  }

  if (dir == 'down') {
    return peerKeys.contains('dn_$from') ? 'dn_$from' : from;
  }

  return peerKeys.contains(from) ? from : 'dn_$from';
}

String _shortState(String s) {
  final i = s.lastIndexOf('.');

  return i >= 0 ? s.substring(i + 1) : s;
}

/// Murni & testable: keputusan relay-only untuk sebuah peer. Relay-only

/// (true) = config terbaik & cepat; setelah fallback all-candidates

/// (false, peer ada di [allCandTried]) jangan kembali ke relay-only agar

/// tak ping-pong.

@visibleForTesting
bool relayOnlyFor({
  required String peerUid,

  required Set<String> allCandTried,
}) => !allCandTried.contains(peerUid);

/// Murni & testable: apakah aku (di stage) perlu menawarkan uplink ke X.

/// True bila: aku sendiri di stage, X speaker lain (bukan aku), dan belum

/// ada pc uplink ke X. Menjamin FULL MESH: tiap pasangan speaker punya

/// uplink dua arah (bukan hanya arah pendengar→speaker).

@visibleForTesting
bool meshNeedsOfferTo({
  required String myUid,

  required String peerUid,

  required bool onStage,

  required bool hasUplinkPc,
}) => onStage && peerUid.isNotEmpty && peerUid != myUid && !hasUplinkPc;

/// State + field bersama RoomVoiceSession — dipakai mixin (file `part`).
abstract class _VoiceBase extends ChangeNotifier {
  _VoiceBase({
    required this.roomId,
    required this.myUid,
    this.onEnded,
    this.onStageFull,
    this.onMutedByAdmin,
    SupabaseClient? sb,
  }) : _injectedSb = sb;

  final String roomId;
  final String myUid;
  final VoidCallback? onEnded;
  final VoidCallback? onStageFull;
  final VoidCallback? onMutedByAdmin;

  final SupabaseClient? _injectedSb;
  SupabaseClient get _sb => _injectedSb ?? SupabaseConfig.client;
  bool _joined = false;
  bool _onStage = false;
  bool _muted = true;
  bool _closed = false;
  bool _disposed = false;
  final Set<String> _speakers = {};
  final Map<String, bool> _speakerMuted = {};
  final Set<String> _speakingNow = {};
  int _speakerCount = 0;

  bool get joined => _joined;
  bool get onStage => _onStage;
  bool get muted => _muted;

  /// True selama mic di stage tapi uplink ke pendengar BELUM Connected
  /// (lagi pairing). UI: spinner — bedakan dari mic hijau (connected).
  /// Tanpa listener = mic live → false. Batas 25 dtk lalu tampil apa adanya.
  bool get pairing {
    if (!_onStage || _closed) return false;
    if (_uplinkOk.isNotEmpty) return false;
    // Tanpa target uplink (tak ada pendengar) = mic live → bukan pairing.
    // Jujur: selama ada uplink yang belum Connected, tampil muter —
    // JANGAN timeout jadi hijau palsu lalu diam (laporan "muter-putus-diam").
    return _peers.keys.any((k) => !k.startsWith('dn_'));
  }

  // ── WebRTC ──
  // _peers: uid -> pc. Untuk speaker: pc ke tiap listener (uplink).
  // Untuk listener: pc ke tiap speaker (downlink).
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, List<Map<String, dynamic>>> _pendingCands = {};
  final Map<String, String> _pcIds = {};
  final Map<String, DateTime> _offerSentAt = {};
  final Map<String, DateTime> _lastOfferAt = {};
  final Set<String> _offerBusy = {};
  final Set<int> _seenSignalIds = {};
  MediaStream? _localStream;
  // Stream remote per speaker — dipegang agar tidak di-GC (audio jalan
  // otomatis tanpa renderer).
  final Map<String, MediaStream> _remoteStreams = {};
  // uid yang sudah kukirimi v_join (hindari spam join dobel).
  final Set<String> _joinSentTo = {};

  // ── ICE policy per-peer (relay-only dulu, fallback all-candidates) ──
  // Default relay-only bila Cloudflare TURN tersedia = koneksi deterministik
  // & cepat (pola call 1:1, terukur 1-3 dtk). Bila relay tak menjangkau,
  // `_retryPeerAllCandidates` membuka kandidat host/srflx SEKALI per peer
  // (perbaikan "mic hijau tapi bisu" saat TURN mati / NAT sama).
  // Key = uid peer (dipakai bersama oleh pc uplink `uid` & downlink `dn_uid`
  // karena relay-only yang benar harus KONSISTEN dua arah).
  final Set<String> _allCandTriedPeers = {};
  // yang bisa tiba SETELAH v_speak sesi BARU bila user keluar-masuk cepat
  // (stop() async tak sempat selesai). Tanpa gate, v_bye basi itu memutus
  // peer sesi baru → "masuk lagi ga nyambung". Listener mengabaikan v_bye
  // yang generasinya lebih tua dari v_speak/v_join terakhir si pengirim.
  static int _sessSeq = 0;
  final int sessId = ++_sessSeq;
  final Map<String, int> _peerSess = {};
  // Uplink (pc ke listener) yang sudah Connected — dasar indikator pairing.
  final Set<String> _uplinkOk = {};
  // v_join terakhir yang kuminta per speaker (debounce re-request offer).
  final Map<String, DateTime> _lastJoinReqAt = {};
  // Uplink pertama dibuat per peer — dasar drop "macet total >30 dtk".
  final Map<String, DateTime> _uplinkSince = {};

  StreamSubscription? _signalSub;
  RealtimeChannel? _signalChannel;
  RealtimeChannel? _speakersChannel;
  Timer? _hbTimer;
  Timer? _syncTimer;
  Timer? _reOfferTimer;
  Timer? _levelTimer;
  int _lastSignalId = 0;
  // Cursor speaker (realtime table) — polling cadangan bila realtime macet.
  Timer? _speakersPollTimer;
  // Kontrak lintas-mixin.
  bool _relayOnlyFor(String peerUid);
  Future<void> _sendSignal({
    required String type,
    String? toUid,
    Map<String, dynamic> payload,
  });
  Future<void> _syncMissedSignals();
  Future<void> _fastForwardSignals();
  void _onSignal(Map<String, dynamic> sig);
  Stream<Map<String, dynamic>> _onSignalStream();
  Future<void> _refreshSpeakers();
  void _applySpeakers(Iterable<String> ids);
  Future<void> _applyForcedMute();
  Future<void> _preferOpusCodec(RTCPeerConnection pc);
  Future<void> _makeOfferTo(String peerUid);
  Future<void> _handleOffer(String from, Map<String, dynamic> payload);
  Future<void> _handleAnswer(String from, Map<String, dynamic> payload);
  Future<void> _handleCandidate(String from, Map<String, dynamic> payload);
  Future<void> _retryPeerAllCandidates(String peerUid);
  Future<void> _dropPeer(String uid);
  Future<void> _pollLevels();
  Future<void> _setSpeakerphone(bool on);
  Future<void> stop();
  Future<void> stopSpeaking({bool announce});
}

class RoomVoiceSession extends _VoiceBase
    with _VoiceStageMx, _VoiceSignalMx, _VoicePeerMx {
  /// Max mic nyala bersamaan (cermin server room_voice_join).
  static const int kMaxSpeakers = 6;

  RoomVoiceSession({
    required super.roomId,
    required super.myUid,
    super.onEnded,
    super.onStageFull,
    super.onMutedByAdmin,
    super.sb,
  });
}
