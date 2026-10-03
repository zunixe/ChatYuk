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
class RoomVoiceSession extends ChangeNotifier {
  RoomVoiceSession({
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

  /// Max mic nyala bersamaan (cermin server room_voice_join).
  static const int kMaxSpeakers = 6;

  /// Munge SDP via helper Opus yang sama dengan call 1:1. Tidak pernah
  /// mengembalikan string kosong (fallback ke input bila helper gagal).
  static String _munged(Object? raw) {
    final s = raw as String? ?? '';
    final out = applyOpusLowLatencyPrefs(s);
    return out.isEmpty ? s : out;
  }

  // ── State (baca UI) ──
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

  /// Murni & testable: v_bye basi (generasi lebih tua) wajib diabaikan.
  @visibleForTesting
  static bool isStaleBye(int knownSess, int incomingSess) =>
      incomingSess < knownSess;

  /// Murni & testable: tentukan key pc tujuan kandidat ICE.
  ///
  /// Prioritas: (1) cocokkan `candPcId` dengan nilai di [pcIds] → key pc itu;
  /// (2) fallback hint arah: 'up' (kandidat untuk pc uplink-ku ke `from`) →
  /// key `from`; 'down' (kandidat untuk pc downlink-ku dari `from`) →
  /// key `dn_$from`; (3) tanpa hint → `from` bila ada di [peerKeys], else
  /// `dn_$from`. Mengembalikan key peer (bukan pcId) supaya `_peers[key]`
  /// langsung dapat pc-nya.
  @visibleForTesting
  static String resolveCandidateKey({
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

  /// Snapshot diagnostik untuk sheet debug di HP (tap avatar sendiri).
  /// Isi: state sesi + per-peer (conn/ice/pasangan kandidat terpilih +
  /// level audio in/out). Semua best-effort + timeout — tak boleh hang.
  Future<Map<String, dynamic>> diagnostics() async {
    final peers = <String, dynamic>{};
    double? micLevel;
    for (final entry in _peers.entries.toList()) {
      final key = entry.key;
      final pc = entry.value;
      final isDown = key.startsWith('dn_');
      final info = <String, dynamic>{
        'dir': isDown ? 'down' : 'up',
        'conn': _shortState('${pc.connectionState}'),
        'ice': _shortState('${pc.iceConnectionState}'),
      };
      try {
        final stats = await pc
            .getStats()
            .timeout(const Duration(seconds: 2));
        final byId = <String, dynamic>{};
        for (final r in stats as List? ?? const []) {
          try {
            byId['${(r as dynamic).id}'] = r;
          } catch (_) {}
        }
        String? pairDesc;
        for (final r in byId.values) {
          try {
            final d = r as dynamic;
            if ('${d.type}' != 'candidate-pair') continue;
            final v = Map<String, dynamic>.from(d.values as Map? ?? {});
            final nominated = v['nominated'] == true;
            if (!nominated && pairDesc != null) continue;
            final loc = byId['${v['localCandidateId']}'];
            final rem = byId['${v['remoteCandidateId']}'];
            String cand(Map<String, dynamic>? m) {
              if (m == null) return '?';
              return '${m['candidateType'] ?? '?'}'
                  '/${m['protocol'] ?? '?'}';
            }
            Map<String, dynamic>? vals(dynamic x) {
              try {
                return Map<String, dynamic>.from(x.values as Map);
              } catch (_) {
                return null;
              }
            }
            pairDesc =
                '${cand(vals(loc))}>${cand(vals(rem))}'
                ' ${v['state'] ?? ''}';
            if (nominated) break;
          } catch (_) {}
        }
        if (pairDesc != null) info['pair'] = pairDesc;
        for (final r in byId.values) {
          try {
            final d = r as dynamic;
            final t = '${d.type}';
            if (t != 'inbound-rtp' && t != 'outbound-rtp') continue;
            final v = Map<String, dynamic>.from(d.values as Map? ?? {});
            if ('${v['kind']}' != 'audio' && v['kind'] != null) continue;
            final raw = v['audioLevel'];
            final level = raw is num
                ? raw.toDouble()
                : double.tryParse('$raw');
            if (level == null) continue;
            if (t == 'inbound-rtp') {
              info['in'] = level.toStringAsFixed(3);
            } else {
              info['out'] = level.toStringAsFixed(3);
              if (!isDown) {
                micLevel = micLevel == null
                    ? level
                    : (level > micLevel ? level : micLevel);
              }
            }
          } catch (_) {}
        }
      } catch (_) {}
      peers[key] = info;
    }
    return {
      'sess': sessId,
      'joined': _joined,
      'onStage': _onStage,
      'muted': _muted,
      'pairing': pairing,
      'mic': micLevel == null ? '-' : micLevel.toStringAsFixed(3),
      'speakers': _speakers.toList(),
      'peers': peers,
    };
  }

  static String _shortState(String s) {
    final i = s.lastIndexOf('.');
    return i >= 0 ? s.substring(i + 1) : s;
  }
  Set<String> get speakers => Set.unmodifiable(_speakers);
  bool isMuted(String uid) => _speakerMuted[uid] ?? false;
  bool isSpeaking(String uid) => _speakingNow.contains(uid);
  int get speakerCount => _speakerCount;

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
  bool _relayOnlyFor(String peerUid) =>
      relayOnlyFor(peerUid: peerUid, allCandTried: _allCandTriedPeers);

  /// Murni & testable: keputusan relay-only untuk sebuah peer. Relay-only
  /// (true) = config terbaik & cepat; setelah fallback all-candidates
  /// (false, peer ada di [allCandTried]) jangan kembali ke relay-only agar
  /// tak ping-pong.
  @visibleForTesting
  static bool relayOnlyFor({
    required String peerUid,
    required Set<String> allCandTried,
  }) => !allCandTried.contains(peerUid);

  /// Murni & testable: apakah aku (di stage) perlu menawarkan uplink ke X.
  /// True bila: aku sendiri di stage, X speaker lain (bukan aku), dan belum
  /// ada pc uplink ke X. Menjamin FULL MESH: tiap pasangan speaker punya
  /// uplink dua arah (bukan hanya arah pendengar→speaker).
  @visibleForTesting
  static bool meshNeedsOfferTo({
    required String myUid,
    required String peerUid,
    required bool onStage,
    required bool hasUplinkPc,
  }) =>
      onStage && peerUid.isNotEmpty && peerUid != myUid && !hasUplinkPc;

  // Generasi sesi (monotonik per proses): teardown sesi LAMA mengirim v_bye
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

  // ── Buka sesi sebagai PENDENGAR ──
  Future<void> startListening() async {
    if (_closed || _joined) return;
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    _signalSub = _onSignalStream().listen(
      _onSignal,
      onError: (e) => dlog('[RoomVoice] signal stream error: $e'),
    );
    await _fastForwardSignals();
    // Polling cadangan (pola broadcast): realtime bisa terlewat.
    _syncTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_closed) return;
      unawaited(_syncMissedSignals());
    });
    // Daftar speaker live: realtime table + polling cadangan 20 dtk.
    _speakersChannel = _sb
        .channel('room-voice-speakers-$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_voice_speakers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (_) => unawaited(_refreshSpeakers()),
        )
        .subscribe((status, err) {
          if (err != null) dlog('[RoomVoice] speakers realtime error: $err');
        });
    _speakersPollTimer =
        Timer.periodic(const Duration(seconds: 20), (_) {
      if (_closed) return;
      unawaited(_refreshSpeakers());
    });
    // Level bicara: getStats inbound-rtp audio tiap 1 dtk (pemicu animasi
    // avatar — 1.5 dtk terasa telat saat mulai bicara).
    _levelTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (_closed) return;
      unawaited(_pollLevels());
    });
    await _sendSignal(type: 'v_join', payload: {
      'ts': DateTime.now().toIso8601String(),
      'sess': sessId,
    });
    await _refreshSpeakers();
    _joined = true;
    notifyListeners();
    // Burst sinkron: realtime bisa telat/hilang; kejar sinyal ≤30 dtk yang
    // terlewat dalam 5 dtk pertama supaya handshake kenceng.
    _burstSync();
  }

  /// Kejar sinyal + daftar speaker beberapa kali cepat setelah join (cadangan
  /// realtime). Idempoten (dedup `_seenSignalIds`) — aman dipanggil berulang.
  ///
  /// Tick RAPAT di fase awal (400/1200/2500 ms) supaya handshake
  /// v_speak→v_join→v_offer tak tertahan menunggu realtime/`_syncTimer` (dulu
  /// hanya 1.5s/4s → connect terasa lambat vs call 1:1). Tick terakhir 4s
  /// sebagai jaring pengaman.
  void _burstSync() {
    for (final ms in [400, 1200, 2500, 4000]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (_closed) return;
        unawaited(_syncMissedSignals());
        unawaited(_refreshSpeakers());
      });
    }
  }

  // ── Naik stage + mic nyala. Return false bila panggung penuh. ──
  Future<bool> startSpeaking() async {
    if (_closed || _onStage) return _onStage;
    if (!_joined) await startListening();
    if (_closed) return false;
    // Guard server (max 6). RPC me-return speakers aktif.
    // Timeout WAJIB: RPC gantung = _voiceJoining UI muter selamanya.
    try {
      final res = await _sb
          .rpc('room_voice_join', params: {
            'p_room_id': roomId,
          })
          .timeout(const Duration(seconds: 10));
      final map = res is Map ? Map<String, dynamic>.from(res) : const {};
      if (map['ok'] != true) {
        dlog('[VOICE] stage full');
        onStageFull?.call();
        return false;
      }
      _applySpeakers(((map['speakers'] as List?) ?? const []).map((e) => '$e'));
    } catch (e) {
      dlog('[VOICE] join error: $e');
      return false;
    }
    // Timeout WAJIB: getUserMedia bisa gantung di sebagian HP (mic dipakai
    // app lain / izin menggantung) → join tak pernah selesai.
    // Constraint eksplisit (sama seperti call 1:1): AEC/NS/AGC + perbaikan
    // Google (highpass/typing) + mono → suara jernih & hemat. Tanpa ini tiap
    // device pakai default berbeda (Xiaomi pernah pilih mic jauh = pelan).
    // Fallback: bila device menolak constraint (Overconstrained), coba tanpa
    // constraint supaya voice tetap jalan (jangan gagalkan sesi).
    const audioConstraints = {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
      'googEchoCancellation': true,
      'googAutoGainControl': true,
      'googNoiseSuppression': true,
      'googHighpassFilter': true,
      'googTypingNoiseDetection': true,
      'channelCount': 1,
    };
    try {
      _localStream = await navigator.mediaDevices
          .getUserMedia({'audio': audioConstraints, 'video': false})
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      dlog('[VOICE] getUserMedia (constraint) failed: $e — coba tanpa constraint');
      try {
        _localStream = await navigator.mediaDevices
            .getUserMedia({'audio': true, 'video': false})
            .timeout(const Duration(seconds: 10));
      } catch (e2) {
        dlog('[VOICE] getUserMedia audio failed: $e2');
        try {
          await _sb.rpc('room_voice_leave', params: {'p_room_id': roomId});
        } catch (_) {}
        return false;
      }
    }
    // Pilih mic terbaik (audioinput pertama): di sebagian device default bisa
    // jatuh ke mic jauh → suara pelan. Best-effort (pola call 1:1).
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      for (final d in devices) {
        if (d.kind == 'audioinput' && d.deviceId.isNotEmpty) {
          await Helper.selectAudioInput(d.deviceId);
          break;
        }
      }
    } catch (_) {}
    _onStage = true;
    _muted = false;
    _speakers.add(myUid);
    // Pastikan mic native UNMUTE saat mulai stage (bisa tertinggal true dari
    // sesi sebelumnya → "mic hijau tapi bisu").
    for (final t in _localStream?.getAudioTracks() ?? const []) {
      try {
        t.enabled = true;
      } catch (_) {}
      try {
        await Helper.setMicrophoneMute(false, t);
      } catch (_) {}
    }
    // Audio route: speakerphone WAJIB agar suara lawan terdengar kencang
    // (default earpiece/volume rendah = "mic hijau tapi bisu"). Best-effort:
    // jangan gagalkan sesi bila tak didukung device.
    await _setSpeakerphone(true);
    // Pairing dimulai: hijau (connected) hanya setelah uplink Connected.
    _uplinkOk.clear();
    // Heartbeat stage tiap 15 dtk (pola broadcast).
    _hbTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_closed || !_onStage) return;
      try {
        await _sb.rpc('room_voice_heartbeat', params: {'p_room_id': roomId});
      } catch (_) {}
    });
    // Umumkan ke pendengar: balas dengan v_join terarah → ku-offer.
    // Sertakan generasi sesi supaya v_bye basi sesi lama tak membunuh peer baru.
    await _sendSignal(type: 'v_speak', payload: {
      'ts': DateTime.now().toIso8601String(),
      'sess': sessId,
    });
    // OPSI B — percepat handshake: selain menunggu `v_join` dari pendengar,
    // langsung tawarkan uplink ke speaker lain yang SUDAH diketahui dari
    // daftar stage. Memotong 1 round-trip (v_join) sebelum offer pertama.
    // Idempoten & aman duplikat: `_makeOfferTo` di-guard `_offerBusy` +
    // cek connectionState; sisi lawan juga mengirim v_join/offer sendiri →
    // `_handleOffer` mengabaikan offer saat pc sudah Connecting/Connected.
    for (final uid in _speakers.toList()) {
      if (uid == myUid) continue;
      unawaited(_makeOfferTo(uid));
    }
    _burstSync();
    // Re-offer watchdog: pc mati / answer macet >8 dtk / macet total >30 dtk.
    _reOfferTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (_closed || !_onStage) return;
      final now = DateTime.now();
      for (final entry in _peers.entries.toList()) {
        // Downlink (dn_uid, suara MASUK dari speaker lain) JANGAN dioffer:
        // _makeOfferTo butuh uid asli — key dn_ menimpa pc downlink (suara
        // masuk mati!) + offer ke "uid" yang tak ada. Downlink pulih via
        // re-request v_join (lihat onConnectionState downlink).
        if (entry.key.startsWith('dn_')) continue;
        // Uplink macet total >30 dtk tanpa pernah Connected: buang (spinner
        // abadi + pc zombie). v_join segar dari pendengar membangun ulang
        // bila mereka masih ada.
        final since = _uplinkSince[entry.key];
        if (since != null &&
            now.difference(since) > const Duration(seconds: 30) &&
            !_uplinkOk.contains(entry.key)) {
          unawaited(_dropPeer(entry.key));
          continue;
        }
        final pc = entry.value;
        final st = pc.connectionState;
        // CONNECTED = sehat → JANGAN diapa-apakan. Dulu timer ini tetap
        // re-offer tiap >8 dtk walau sudah Connected → close+rebuild pc →
        // siklus "putus-nyambung" (~8 dtk) yang memutus audio. Ini akar
        // "kadang ada suara, kadang muter".
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          continue;
        }
        // FALLBACK relay→all-candidates: relay-only belum Connected >6 dtk
        // (TURN tak menjangkau / NAT sama) → buka kandidat host/srflx SEKALI
        // per peer. Meniru grace-timeout fallback call 1:1 ("P2P jalan walau
        // TURN mati"). Dilakukan SEBELUM re-offer biasa supaya negosiasi
        // dibangun ulang dengan config baru (bukan menambah offer di pc lama).
        final since2 = _uplinkSince[entry.key];
        if (_relayOnlyFor(entry.key) &&
            since2 != null &&
            now.difference(since2) > const Duration(seconds: 6)) {
          unawaited(_retryPeerAllCandidates(entry.key));
          continue;
        }
        // Failed/Disconnected benar-benar mati → bangun ulang.
        final dead = st == RTCPeerConnectionState.RTCPeerConnectionStateFailed;
        if (st != null && dead) {
          unawaited(_makeOfferTo(entry.key));
          continue;
        }
        // Disconnected/Connecting baru: beri waktu ICE pulih sendiri
        // (jaringan goyang). Hanya paksa re-offer bila offer terakhir sudah
        // lama (>10 dtk) DAN belum Connected — supaya tak memutus saat pulih.
        final sentAt = _offerSentAt[entry.key];
        if (sentAt != null &&
            now.difference(sentAt) > const Duration(seconds: 10)) {
          unawaited(_makeOfferTo(entry.key));
        }
      }
    });
    notifyListeners();
    return true;
  }

  // ── Turun stage (tetap dengar). ──
  Future<void> stopSpeaking({bool announce = true}) async {
    if (!_onStage) return;
    _onStage = false;
    _muted = true;
    _uplinkOk.clear();
    _hbTimer?.cancel();
    _hbTimer = null;
    try {
      await _sb.rpc('room_voice_leave', params: {'p_room_id': roomId});
    } catch (_) {}
    if (announce) {
      await _sendSignal(type: 'v_bye', payload: {'sess': sessId});
    }
    // Tutup pc uplink (ke listener); pc downlink (dari speaker lain)
    // tetap — kita masih pendengar.
    for (final uid in _peers.keys.toList()) {
      if (_speakers.contains(uid)) continue;
      await _dropPeer(uid);
    }
    _speakers.remove(myUid);
    // Turun stage: matikan mic native dulu (bukan hanya track.stop()).
    for (final t in _localStream?.getAudioTracks() ?? const []) {
      try {
        await Helper.setMicrophoneMute(true, t);
      } catch (_) {}
      try {
        t.enabled = false;
      } catch (_) {}
      try {
        t.stop();
      } catch (_) {}
    }
    _localStream = null;
    notifyListeners();
  }

  // ── Audio route: paksa speakerphone (best-effort, aman di semua env). ──
  Future<void> _setSpeakerphone(bool on) async {
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (_) {}
  }

  /// Paksa codec Opus untuk transceiver audio (latency rendah + FEC).
  /// Dipanggil setelah addTrack/setRemoteDescription & sebelum
  /// createOffer/createAnswer. Best-effort: gagal → pakai default.
  Future<void> _preferOpusCodec(RTCPeerConnection pc) async {
    if (_closed) return;
    try {
      final transceivers = await pc.getTransceivers();
      for (final t in transceivers) {
        try {
          final kind = t.receiver.track?.kind;
          if (kind != null && kind != 'audio') continue;
          await t.setCodecPreferences([
            RTCRtpCodecCapability(
              mimeType: 'audio/opus',
              clockRate: 48000,
              channels: 2,
              sdpFmtpLine: 'minptime=10;useinbandfec=1',
            ),
          ]);
        } catch (_) {}
      }
    } catch (_) {}
  }

  // ── Mute/unmute mic sendiri (tetap di stage, tanpa renegosiasi). ──
  // Pakai DUA jalur agar benar-benar senyap di semua device:
  //  (1) track.enabled=false (lewat API track),
  //  (2) Helper.setMicrophoneMute (mute di AudioDeviceModule native) — pada
  //      sebagian device `enabled=false` saja TIDAK memutus mic ("mic di-off
  //      tapi tetap kedengar"). Native mute menutup celah itu.
  Future<void> setMuted(bool value) async {
    if (!_onStage) return;
    _muted = value;
    for (final t in _localStream?.getAudioTracks() ?? const []) {
      try {
        t.enabled = !value;
      } catch (_) {}
      try {
        await Helper.setMicrophoneMute(value, t);
      } catch (_) {}
    }
    await _sendSignal(type: 'v_mute', payload: {'muted': value});
    notifyListeners();
  }

  // ── Tutup total (keluar voice). ──
  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    // Kembalikan route audio ke default (lepas speakerphone paksa).
    await _setSpeakerphone(false);
    _hbTimer?.cancel();
    _syncTimer?.cancel();
    _reOfferTimer?.cancel();
    _levelTimer?.cancel();
    _speakersPollTimer?.cancel();
    await _signalSub?.cancel();
    for (final ch in [_signalChannel, _speakersChannel]) {
      if (ch == null) continue;
      try {
        _sb.removeChannel(ch);
      } catch (_) {}
    }
    _signalChannel = null;
    _speakersChannel = null;
    if (_onStage) {
      _onStage = false;
      try {
        await _sb.rpc('room_voice_leave', params: {'p_room_id': roomId});
      } catch (_) {}
      await _sendSignal(type: 'v_bye', payload: {'sess': sessId});
    }
    _uplinkOk.clear();
    _peerSess.clear();
    _lastJoinReqAt.clear();
    _uplinkSince.clear();
    // Matikan mic DULU (native) lalu stop track — sebagian device tidak
    // melepas mic hanya dengan track.stop() ("keluar room mic masih nyala").
    for (final t in _localStream?.getAudioTracks() ?? const []) {
      try {
        await Helper.setMicrophoneMute(true, t);
      } catch (_) {}
      try {
        t.enabled = false;
      } catch (_) {}
      try {
        t.stop();
      } catch (_) {}
    }
    _localStream = null;
    for (final pc in _peers.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _peers.clear();
    _remoteStreams.clear();
    _speakers.clear();
    _speakerMuted.clear();
    _speakingNow.clear();
    _pendingCands.clear();
    _pcIds.clear();
    _offerSentAt.clear();
    _joinSentTo.clear();
    _allCandTriedPeers.clear();
    onEnded?.call();
    // dispose() memanggil stop() lalu super.dispose() — notify di sini
    // akan melempar "used after dispose". Lewati bila sudah dispose.
    if (!_disposed) notifyListeners();
  }

  // ── Sinyal ──
  Stream<Map<String, dynamic>> _onSignalStream() {
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    final channel = _sb.channel('room-voice-$roomId-$myUid');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'room_voice_signals',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'room_id',
        value: roomId,
      ),
      callback: (payload) {
        if (controller.isClosed) return;
        final row = Map<String, dynamic>.from(payload.newRecord);
        if ('${row['from_uid']}' == myUid) return;
        // Hanya untukku atau broadcast.
        final to = '${row['to_uid'] ?? ''}';
        if (to.isNotEmpty && to != myUid) return;
        controller.add(row);
      },
    );
    channel.subscribe((status, err) {
      if (err != null) dlog('[RoomVoice] signal realtime error: $err');
    });
    _signalChannel = channel;
    controller.onCancel = () {
      try {
        _sb.removeChannel(channel);
      } catch (_) {}
    };
    return controller.stream;
  }

  Future<void> _sendSignal({
    required String type,
    String? toUid,
    Map<String, dynamic> payload = const {},
  }) async {
    try {
      await _sb.from('room_voice_signals').insert({
        'room_id': roomId,
        'from_uid': myUid,
        'to_uid': toUid,
        'type': type,
        'payload': payload,
      });
    } catch (e) {
      dlog('[VOICE] sendSignal $type error: $e');
    }
  }

  Future<void> _syncMissedSignals() async {
    if (_closed) return;
    try {
      final rows = await _sb
          .from('room_voice_signals')
          .select()
          .eq('room_id', roomId)
          .gt('id', _lastSignalId)
          .gte('created_at', DateTime.now()
              .toUtc()
              .subtract(const Duration(seconds: 30))
              .toIso8601String())
          .order('id')
          .limit(200);
      for (final r in (rows as List? ?? const [])) {
        final m = Map<String, dynamic>.from(r as Map);
        _lastSignalId = max(_lastSignalId, ((m['id'] ?? 0) as num).toInt());
        _onSignal(m);
      }
    } catch (_) {}
  }

  Future<void> _fastForwardSignals() async {
    try {
      final row = await _sb
          .from('room_voice_signals')
          .select('id')
          .eq('room_id', roomId)
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();
      _lastSignalId = (((row as Map?) ?? const {})['id'] as num?)?.toInt() ?? 0;
    } catch (_) {}
  }

  void _onSignal(Map<String, dynamic> sig) {
    if (_closed) return;
    final sid = ((sig['id'] ?? 0) as num).toInt();
    if (sid > 0) {
      if (!_seenSignalIds.add(sid)) return;
      _lastSignalId = max(_lastSignalId, sid);
    }
    final ca = DateTime.tryParse('${sig['created_at'] ?? ''}');
    if (ca != null &&
        DateTime.now().toUtc().difference(ca.toUtc()) >
            const Duration(seconds: 30)) {
      return;
    }
    final type = '${sig['type'] ?? ''}';
    final from = '${sig['from_uid'] ?? ''}';
    if (from.isEmpty || from == myUid) return;
    final payload = (sig['payload'] as Map?)?.cast<String, dynamic>() ?? {};

    switch (type) {
      case 'v_speak':
        // Speaker baru (X) mengumumkan diri.
        // Catat generasinya — v_bye lebih tua dari ini diabaikan.
        final speakSess = (payload['sess'] as num?)?.toInt();
        if (speakSess != null) {
          final known = _peerSess[from] ?? -1;
          if (speakSess > known) _peerSess[from] = speakSess;
        }
        _joinSentTo.add(from);
        _speakers.add(from);
        // FULL MESH 3-6 orang: tiap pasangan butuh DUA arah audio (aku→X dan
        // X→aku). Bila aku JUGA di stage, aku harus menawarkan uplink-ku ke X
        // (aku→X). Tanpa ini arah dari speaker-lama ke speaker-baru TIDAK
        // pernah terbentuk (hanya v_join → X offer ke aku = X→aku) → bertiga
        // sebagian pasangan bisu. Bila aku pendengar (tidak di stage), cukup
        // balas v_join (minta X offer ke aku).
        if (_onStage) {
          unawaited(_makeOfferTo(from));
        } else {
          unawaited(_sendSignal(type: 'v_join', toUid: from, payload: {
            'ts': DateTime.now().toIso8601String(),
            'sess': sessId,
          }));
        }
        notifyListeners();
        break;
      case 'v_join':
        // Pendengar minta audio → aku offer (hanya bila aku di stage).
        if (_onStage) unawaited(_makeOfferTo(from));
        break;
      case 'v_offer':
        {
          final ca2 = DateTime.tryParse('${sig['created_at'] ?? ''}') ??
              DateTime.now().toUtc();
          final last = _lastOfferAt[from];
          if (last != null && !ca2.isAfter(last)) return;
          _lastOfferAt[from] = ca2;
          unawaited(_handleOffer(from, payload));
        }
        break;
      case 'v_answer':
        unawaited(_handleAnswer(from, payload));
        break;
      case 'v_cand':
        unawaited(_handleCandidate(from, payload));
        break;
      case 'v_bye':
        {
          // Abaikan v_bye basi: teardown sesi lama yang telat tiba setelah
          // user keluar-masuk cepat (sesi baru sudah v_speak duluan).
          final byeSess = (payload['sess'] as num?)?.toInt() ?? -1;
          final knownSess = _peerSess[from] ?? -1;
          if (byeSess >= 0 && isStaleBye(knownSess, byeSess)) break;
          _peerSess.remove(from);
          unawaited(_dropPeer(from));
          _speakers.remove(from);
          _speakerMuted.remove(from);
          _speakingNow.remove(from);
          notifyListeners();
        }
        break;
      case 'v_mute':
        {
          final to = '${sig['to_uid'] ?? ''}';
          if (to.isNotEmpty && to != myUid) break;
          final muted = payload['muted'] != false;
          if (to == myUid) {
            // Mute paksa admin/owner: matikan track + turun stage.
            unawaited(_applyForcedMute());
          } else {
            _speakerMuted[from] = muted;
            if (muted) _speakingNow.remove(from);
            notifyListeners();
          }
        }
        break;
    }
  }

  Future<void> _applyForcedMute() async {
    if (!_onStage) return;
    try {
      for (final t in _localStream?.getAudioTracks() ?? const []) {
        t.enabled = false;
      }
    } catch (_) {}
    _muted = true;
    await stopSpeaking(announce: false);
    await _sendSignal(type: 'v_mute', payload: {'muted': true});
    onMutedByAdmin?.call();
    if (!_closed) notifyListeners();
  }

  // ── Daftar speaker (realtime table + refresh) ──
  Future<void> _refreshSpeakers() async {
    if (_closed) return;
    try {
      // Baca langsung (RLS select mengizinkan); fallback: biarkan state lama.
      final rows = await _sb
          .from('room_voice_speakers')
          .select('uid')
          .eq('room_id', roomId)
          .limit(20);
      final ids = <String>{
        for (final r in (rows as List? ?? const [])) '${(r as Map)['uid'] ?? ''}'
      }..removeWhere((e) => e.isEmpty);
      // Baris server milikku dari SESI SEBELUMNYA (keluar-masuk cepat,
      // leave belum diproses) jangan dianggap stage-ku sekarang — stage-ku
      // ditentukan state lokal. Selalu sertakan diriku bila di stage
      // (heartbeat-ku mungkin belum terbaca realtime).
      ids.remove(myUid);
      if (_onStage) ids.add(myUid);
      _applySpeakers(ids);
    } catch (_) {}
  }

  void _applySpeakers(Iterable<String> ids) {
    final next = Set<String>.from(ids)..removeWhere((e) => e.isEmpty);
    // FULL MESH: bila aku di stage, tawarkan uplink ke speaker lain yang
    // BELUM punya pc (baru muncul di daftar). Menjamin tiap pasangan
    // terbentuk walau `v_speak`/v_join terlewat (realtime telat). Idempoten:
    // `_makeOfferTo` guard `_offerBusy` + cek pc existing.
    if (_onStage) {
      for (final uid in next) {
        if (meshNeedsOfferTo(
          myUid: myUid,
          peerUid: uid,
          onStage: _onStage,
          hasUplinkPc: _peers.containsKey(uid),
        )) {
          unawaited(_makeOfferTo(uid));
        }
      }
    }
    // Peer yang hilang dari stage → drop.
    // PENTING: iterasi hanya pc UPLINK (key uid asli). Key downlink `dn_<uid>`
    // TIDAK boleh dibandingkan dengan daftar speaker (next berisi uid tanpa
    // prefix) — dulu `dn_B` dianggap "bukan speaker" → downlink dari B
    // DIBUANG tiap refresh daftar speaker → koneksi mesh terus dibongkar
    // (gejala "3 orang semua muter-putus"). Downlink dibersihkan lewat
    // `_dropPeer`/v_bye saat peer benar-benar keluar, bukan di sini.
    for (final uid in _peers.keys.toList()) {
      if (uid.startsWith('dn_')) continue;
      if (uid == myUid) continue;
      if (!next.contains(uid) && !_joinSentTo.contains(uid)) {
        unawaited(_dropPeer(uid));
      }
    }
    _speakers
      ..clear()
      ..addAll(next);
    if (_onStage) _speakers.add(myUid);
    _speakerCount = _speakers.length;
    notifyListeners();
  }

  // ── Offer/answer/candidate: TRICKLE ICE ──
  // Offer/answer dikirim SEGERA setelah setLocalDescription; kandidat menyusul
  // via v_cand (antrean _pendingCands menampung yang datang duluan).
  // Dulu non-trickle (tunggu gathering ≤2 dtk) → handshake lambat + macet
  // total bila gathering tak kunjung complete di jaringan aneh.

  Future<void> _makeOfferTo(String peerUid) async {
    if (_closed || !_onStage || _localStream == null) return;
    if (peerUid.isEmpty || peerUid == myUid) return;
    if (_offerBusy.contains(peerUid)) return;
    _offerBusy.add(peerUid);
    try {
      // Uplink ke peerUid ada di key `peerUid`; downlink dari peerUid yang
      // sama ada di key `dn_$peerUid` (mesh dua arah: aku dengar dia VIA pc
      // downlink, dia dengar aku VIA pc uplink). Key BERBEDA → tak saling
      // timpa. Tutup hanya pc uplink yang mungkin sudah ada (rebuild offer
      // segar) — JANGAN sentuh pc downlink.
      final old = _peers[peerUid];
      if (old != null) {
        // pc existing masih hidup/menghubung → JANGAN rebuild (dulu selalu
        // close → memutus koneksi sehat yang sudah Connecting/Connected).
        final st = old.connectionState;
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
          return;
        }
        try {
          await old.close();
        } catch (_) {}
        _peers.remove(peerUid);
        _pcIds.remove(peerUid);
        _pendingCands.remove(peerUid);
      }
      final pc = await createPeerConnection(
        await CallConfig.getPeerConfig(relayOnly: _relayOnlyFor(peerUid)),
      );
      _peers[peerUid] = pc;
      // Set pcId LEBIH DULU: onIceCandidate di bawah membacanya saat kandidat
      // mengalir (yang bisa mulai tepat setelah setLocalDescription) — bila
      // di-set belakangan, kandidat pertama terkirim dengan pcId null →
      // penerima tak bisa me-routing → ICE gagal ("spinner muter terus").
      final pcId = 'up_${DateTime.now().microsecondsSinceEpoch}';
      _pcIds[peerUid] = pcId;
      _uplinkSince.putIfAbsent(peerUid, () => DateTime.now());
      final tracks = _localStream!.getAudioTracks();
      if (tracks.isEmpty) return;
      await pc.addTrack(tracks.first, _localStream!);
      // Opus low-latency + FEC: setelah addTrack (transceiver ada) & sebelum
      // createOffer. Best-effort (pola call 1:1 _preferOpusCodec).
      await _preferOpusCodec(pc);
      pc.onIceCandidate = (c) {
        _sendSignal(type: 'v_cand', toUid: peerUid, payload: {
          'candidate': c.toMap(),
          // pcId arah uplink TARGET — agar penerima menaruh kandidat ke pc
          // downlink yang benar (bukan tertukar saat mesh dua arah).
          'pcId': _pcIds[peerUid],
          'dir': 'down',
        });
      };
      pc.onConnectionState = (st) {
        if (!identical(_peers[peerUid], pc)) return;
        // Connected = uplink hidup → matikan status pairing.
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _uplinkOk.add(peerUid);
        } else if (st ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
            st ==
                RTCPeerConnectionState
                    .RTCPeerConnectionStateDisconnected) {
          _uplinkOk.remove(peerUid);
        }
        // Disconnected SERING transient di Android (jaringan goyang) & ICE
        // pulih sendiri — JANGAN langsung re-offer/close (dulu ini memutus
        // koneksi sehat → audio "kadang ada kadang muter"). Cukup serahkan
        // ke watchdog (_reOfferTimer) yang menunggu >10 dtk sebelum membangun
        // ulang. Failed/Closed = benar-benar mati → drop + jadwalkan re-join
        // terarah agar koneksi pulih sendiri (bukan hilang sampai lawan join).
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          unawaited(_dropPeer(peerUid));
          if (_onStage && !_closed && _speakers.contains(peerUid)) {
            Future.delayed(const Duration(seconds: 2), () {
              if (_closed || !_onStage) return;
              if (_peers.containsKey(peerUid)) return;
              if (!_speakers.contains(peerUid)) return;
              unawaited(_sendSignal(type: 'v_join', toUid: peerUid, payload: {
                'ts': DateTime.now().toIso8601String(),
                'sess': sessId,
              }));
            });
          }
        }
        notifyListeners();
      };
      final offer = await pc.createOffer();
      // Opus low-latency + FEC (helper yang sama dengan call 1:1).
      final offerMunged = applyOpusLowLatencyPrefs(offer.sdp ?? '');
      final localOffer = RTCSessionDescription(
        offerMunged.isEmpty ? (offer.sdp ?? '') : offerMunged,
        offer.type,
      );
      await pc.setLocalDescription(localOffer);
      // Trickle: kirim LANGSUNG (tanpa tunggu gathering) — kandidat susul.
      final desc = await pc.getLocalDescription();
      _offerSentAt[peerUid] = DateTime.now();
      await _sendSignal(type: 'v_offer', toUid: peerUid, payload: {
        'sdp': (desc ?? offer).toMap(),
        'pcId': pcId,
        // Beritahu policy ICE-ku agar penerima MIRROR (dua arah konsisten).
        // Bila aku sudah fallback all-candidates, penerima ikut melepas
        // relay-only → negosiasi punya kandidat yang bisa berpasangan.
        'relay': _relayOnlyFor(peerUid),
      });
      notifyListeners();
    } catch (e) {
      dlog('[VOICE] offer to $peerUid failed: $e');
    } finally {
      _offerBusy.remove(peerUid);
    }
  }

  Future<void> _handleOffer(String from, Map<String, dynamic> payload) async {
    final sdp = payload['sdp'] as Map<String, dynamic>?;
    if (sdp == null || _closed) return;
    final offerPcId = '${payload['pcId'] ?? ''}';
    // MIRROR policy ICE pengirim: bila dia offer dengan all-candidates
    // (relay=false), tandai peer ini juga → pc jawabanku pakai all-candidates
    // agar kandidat dua arah bisa berpasangan (mencegah mixed relay/host
    // yang tak pernah connect).
    if (payload['relay'] == false) {
      _allCandTriedPeers.add(from);
    }
    try {
      // Downlink selalu key 'dn_$from' (terpisah dari uplink key `from`).
      final key = 'dn_$from';
      var pc = _peers[key];
      if (pc != null) {
        // Offer duplikat (retry lawan) saat downlink MASIH hidup → abaikan,
        // jangan close-rebuild (dulu ini memutus audio yang sedang jalan).
        final st = pc.connectionState;
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
          return;
        }
        // GLARE/dedup: offer dengan pcId yang SAMA & remoteDescription sudah
        // terpasang = duplikat (realtime + burst sync). Jangan close-rebuild
        // — rebuild saat state have-remote-offer memicu error
        // "cannot createAnswer in state other than have-remote-offer" saat
        // negosiasi mesh 3+ orang.
        if (offerPcId.isNotEmpty && _pcIds[key] == offerPcId) {
          final rd = await pc.getRemoteDescription();
          if (rd != null) return;
        }
        try {
          await pc.close();
        } catch (_) {}
        _peers.remove(key);
      }
      pc = await createPeerConnection(
        await CallConfig.getPeerConfig(relayOnly: _relayOnlyFor(from)),
      );
      _peers[key] = pc;
      // Tandai arah downlink + pcId supaya routing kandidat ICE pasti
      // (bukan lagi menebak via containsKey yang ambigu saat mesh dua arah).
      final dnPcId = offerPcId.isNotEmpty
          ? offerPcId
          : 'dn_${DateTime.now().microsecondsSinceEpoch}';
      _pcIds[key] = dnPcId;
      pc.onConnectionState = (st) {
        if (_closed || !identical(_peers[key], pc)) return;
        // Connected = downlink sehat → bersihkan timer re-join.
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _lastJoinReqAt.remove(from);
          notifyListeners();
          return;
        }
        // Disconnected transient (Android) → ICE biasanya pulih sendiri,
        // JANGAN langsung minta join ulang (dulu memicu close+rebuild yang
        // memutus audio). Failed/Closed = benar-benar mati baru re-join.
        final hardDead =
            st == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateClosed;
        if (hardDead) {
          _remoteStreams.remove(from);
          _speakingNow.remove(from);
          // Downlink mati total: minta offer ulang ke speaker (dia yang
          // pegang uplink). Debounce 4 dtk; hanya bila dia masih di stage.
          if (_speakers.contains(from)) {
            final now = DateTime.now();
            final last = _lastJoinReqAt[from];
            if (last == null ||
                now.difference(last) > const Duration(seconds: 4)) {
              _lastJoinReqAt[from] = now;
              unawaited(_sendSignal(type: 'v_join', toUid: from, payload: {
                'ts': now.toIso8601String(),
                'sess': sessId,
              }));
            }
          }
          notifyListeners();
        }
      };
      // FALLBACK relay→all-candidates untuk PENDENGAR (tanpa pc uplink —
      // watchdog `_reOfferTimer` hanya iterasi uplink). Bila downlink ini
      // belum Connected setelah 6 dtk & masih relay-only → buka semua
      // kandidat. `_retryPeerAllCandidates` menutup pc ini & minta offer
      // ulang (v_join) → dibangun lagi dengan config all-candidates.
      final dnPc = pc;
      Future.delayed(const Duration(seconds: 6), () {
        if (_closed || !identical(_peers[key], dnPc)) return;
        if (dnPc.connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          return;
        }
        if (_relayOnlyFor(from)) unawaited(_retryPeerAllCandidates(from));
      });
      pc.onTrack = (event) async {
        // Fallback: sebagian device tak mengirim event.streams → bikin
        // stream sendiri agar audio tetap disimpan & diputar (pola call).
        var stream =
            event.streams.isNotEmpty ? event.streams.first : null;
        if (stream == null) {
          stream = await createLocalMediaStream('remote-$from');
          try {
            await stream.addTrack(event.track);
          } catch (_) {}
        }
        if (!_closed) {
          _remoteStreams[from] = stream;
          notifyListeners();
        }
      };
      pc.onIceCandidate = (c) {
        _sendSignal(type: 'v_cand', toUid: from, payload: {
          'candidate': c.toMap(),
          // pcId arah downlink-ku TARGET (offerPcId dari speaker) — agar
          // speaker menaruh kandidat ke pc uplink yang benar.
          'pcId': dnPcId,
          'dir': 'up',
        });
      };
      await pc.setRemoteDescription(
        RTCSessionDescription(
          _munged(sdp['sdp']),
          sdp['type'],
        ),
      );
      for (final c in List<Map<String, dynamic>>.from(
          _pendingCands[dnPcId] ?? const [])) {
        try {
          await pc.addCandidate(RTCIceCandidate(
            c['candidate'] ?? '',
            c['sdpMid'],
            (c['sdpMLineIndex'] as num?)?.toInt(),
          ));
        } catch (_) {}
      }
      _pendingCands.remove(dnPcId);
      // Opus low-latency + FEC untuk audio jawaban (setelah setRemoteDescription
      // offer, sebelum createAnswer). Best-effort.
      await _preferOpusCodec(pc);
      final answer = await pc.createAnswer();
      final answerMunged = applyOpusLowLatencyPrefs(answer.sdp ?? '');
      final localAnswer = RTCSessionDescription(
        answerMunged.isEmpty ? (answer.sdp ?? '') : answerMunged,
        answer.type,
      );
      await pc.setLocalDescription(localAnswer);
      // Trickle: kirim LANGSUNG (tanpa tunggu gathering) — kandidat susul.
      final desc = await pc.getLocalDescription();
      await _sendSignal(type: 'v_answer', toUid: from, payload: {
        'sdp': (desc ?? answer).toMap(),
        'pcId': offerPcId,
      });
    } catch (e) {
      dlog('[VOICE] handle offer from $from failed: $e');
    }
  }

  Future<void> _handleAnswer(String from, Map<String, dynamic> payload) async {
    final sdp = payload['sdp'] as Map<String, dynamic>?;
    final pc = _peers[from];
    if (sdp == null || pc == null || _closed) return;
    final pcId = '${payload['pcId'] ?? ''}';
    if (pcId.isNotEmpty && pcId != (_pcIds[from] ?? '')) return;
    try {
      final local = await pc.getLocalDescription();
      if (local == null || local.type != 'offer') return;
      final remote = await pc.getRemoteDescription();
      if (remote != null) return;
      await pc.setRemoteDescription(
        RTCSessionDescription(
          _munged(sdp['sdp']),
          sdp['type'],
        ),
      );
      _offerSentAt.remove(from);
      // Flush kandidat tertunda untuk pc uplink ini via pcId (konsisten
      // dengan key yang dipakai _handleCandidate).
      final upPcId = _pcIds[from] ?? '';
      final pend = upPcId.isNotEmpty ? _pendingCands[upPcId] : null;
      for (final c in List<Map<String, dynamic>>.from(pend ?? const [])) {
        try {
          await pc.addCandidate(RTCIceCandidate(
            c['candidate'] ?? '',
            c['sdpMid'],
            (c['sdpMLineIndex'] as num?)?.toInt(),
          ));
        } catch (_) {}
      }
      if (upPcId.isNotEmpty) _pendingCands.remove(upPcId);
    } catch (e) {
      dlog('[VOICE] answer from $from failed: $e');
    }
  }

  Future<void> _handleCandidate(
    String from,
    Map<String, dynamic> payload,
  ) async {
    final c = payload['candidate'] as Map<String, dynamic>?;
    if (c == null || _closed) return;
    // Routing PASTI via pcId yang dikirim: cari pc yang _pcIds-nya cocok.
    // Sebelumnya menebak via containsKey(from) → ambigu saat mesh dua arah
    // (uid sama punya pc uplink `from` DAN downlink `dn_from`) → kandidat
    // masuk slot salah → ICE gagal / "mic hijau tapi bisu".
    final candPcId = '${payload['pcId'] ?? ''}';
    final key = resolveCandidateKey(
      from: from,
      candPcId: candPcId,
      dir: '${payload['dir'] ?? ''}',
      pcIds: _pcIds,
      peerKeys: _peers.keys.toSet(),
    );
    // Key simpan kandidat tertunda = pcId bila ada (agar flush cocok),
    // else key peer.
    final storeKey = candPcId.isNotEmpty ? candPcId : key;
    final pc = _peers[key];
    if (pc == null) {
      _pendingCands.putIfAbsent(storeKey, () => []).add(c);
      return;
    }
    try {
      final remote = await pc.getRemoteDescription();
      if (remote == null) {
        _pendingCands.putIfAbsent(storeKey, () => []).add(c);
        return;
      }
    } catch (_) {
      _pendingCands.putIfAbsent(storeKey, () => []).add(c);
      return;
    }
    try {
      await pc.addCandidate(RTCIceCandidate(
        c['candidate'] ?? '',
        c['sdpMid'],
        (c['sdpMLineIndex'] as num?)?.toInt(),
      ));
    } catch (_) {}
  }

  /// Fallback relay-only → semua kandidat (host/srflx/relay) UNTUK SATU PEER.
  /// Dipakai bila relay-only belum juga Connected (TURN tak terjangkau / NAT
  /// sama) — menyelamatkan audio mesh walau Cloudflare TURN mati. SEKALI per
  /// peer (guard `_allCandTriedPeers`). Beda dari call 1:1 (pc tunggal): di
  /// mesh, satu peer punya pc uplink (`uid`) & downlink (`dn_uid`) — keduanya
  /// dibangun ulang dengan config all-candidates supaya konsisten dua arah.
  Future<void> _retryPeerAllCandidates(String peerUid) async {
    if (_closed) return;
    if (!_allCandTriedPeers.add(peerUid)) return; // sudah pernah → stop
    dlog('[VOICE] fallback relay→all-candidates untuk $peerUid');
    // Tutup pc uplink + downlink peer ini agar negosiasi dibangun ulang
    // dengan config baru (bukan menambah offer di pc relay lama).
    for (final k in [peerUid, 'dn_$peerUid']) {
      final pc = _peers.remove(k);
      try {
        await pc?.close();
      } catch (_) {}
      _pendingCands.remove(k);
      _pcIds.remove(k);
      _offerSentAt.remove(k);
    }
    _uplinkOk.remove(peerUid);
    _uplinkSince[peerUid] = DateTime.now();
    if (_closed) return;
    // Uplink: aku (jika di stage) tawarkan ulang dengan all-candidates.
    if (_onStage && _speakers.contains(peerUid)) {
      unawaited(_makeOfferTo(peerUid));
    }
    // Downlink: minta speaker menawarkan ulang (dia pegang uplink ke aku).
    if (_speakers.contains(peerUid)) {
      unawaited(_sendSignal(type: 'v_join', toUid: peerUid, payload: {
        'ts': DateTime.now().toIso8601String(),
        'sess': sessId,
      }));
    }
  }

  Future<void> _dropPeer(String uid) async {
    _uplinkOk.remove(uid);
    _uplinkSince.remove(uid);
    for (final k in [uid, 'dn_$uid']) {
      final pc = _peers.remove(k);
      try {
        await pc?.close();
      } catch (_) {}
      _pendingCands.remove(k);
      _pcIds.remove(k);
      _offerSentAt.remove(k);
    }
    _remoteStreams.remove(uid);
    _speakingNow.remove(uid);
    // Peer benar-benar lepas → reset fallback agar koneksi berikutnya ke peer
    // ini mencoba relay-only dulu lagi (config terbaik), bukan terjebak
    // all-candidates dari sesi sebelumnya.
    _allCandTriedPeers.remove(uid);
    notifyListeners();
  }

  // ── Indikator bicara via getStats audioLevel (inbound-rtp audio) ──
  Future<void> _pollLevels() async {
    if (_closed || _peers.isEmpty) {
      if (_speakingNow.isNotEmpty) {
        _speakingNow.clear();
        notifyListeners();
      }
      return;
    }
    final next = <String>{};
    for (final entry in _peers.entries) {
      final key = entry.key;
      final uid = key.startsWith('dn_') ? key.substring(3) : key;
      // Hanya downlink (suara masuk) yang diukur.
      if (!key.startsWith('dn_')) continue;
      try {
        final stats = await entry.value.getStats();
        for (final r in stats) {
          if (r.type != 'inbound-rtp') continue;
          final v = r.values['audioLevel'];
          final level = v is num
              ? v.toDouble()
              : double.tryParse('$v') ?? 0.0;
          if (level > 0.02) next.add(uid);
          break;
        }
      } catch (_) {}
    }
    if (next.length != _speakingNow.length ||
        !next.containsAll(_speakingNow)) {
      _speakingNow
        ..clear()
        ..addAll(next);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
