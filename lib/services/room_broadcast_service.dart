import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config/call_config.dart';
import 'private_room_service.dart';
import '../config/supabase_config.dart';

/// Broadcast video satu-ke-banyak di private room (mesh WebRTC, cap 4).
///
/// - Broadcaster = member yang diberi izin oleh admin (max 4 simultan).
/// - Tiap penonton = 1 peer connection (offer dari broadcaster).
/// - Signaling via tabel room_signals (b_offer/b_answer/b_cand/b_bye/b_join).
/// - Adaptive bitrate: kualitas turun mengikuti jumlah penonton.
/// - Heartbeat via room_broadcasters; watchdog hentikan jika broadcaster hilang.
class RoomBroadcastSession extends ChangeNotifier {
  RoomBroadcastSession({
    required this.roomId,
    required this.isBroadcaster,
    this.onEnded,
  });

  final String roomId;
  final bool isBroadcaster;
  final VoidCallback? onEnded;

  final PrivateRoomService _prv = PrivateRoomService.instance;
  SupabaseClient get _sb => SupabaseConfig.client;

  final Map<String, RTCPeerConnection> _peers = {}; // uid -> pc
  final Map<String, List<Map<String, dynamic>>> _pendingCands = {};
  MediaStream? _localStream;
  RTCPeerConnection? get broadcasterPc =>
      _peers.values.isEmpty ? null : _peers.values.first;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  bool localRendererReady = false;
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> remoteRenderers = {};
  bool remoteReady = false;
  bool hasRemoteVideo = false;

  StreamSubscription? _signalSub;
  RealtimeChannel? _broadcasterSub;
  Timer? _hbTimer;
  Timer? _watchdog;
  Timer? _syncTimer;
  Timer? _rejoinTimer;
  Timer? _reOfferTimer;
  int _lastSignalId = 0;
  bool _closed = false;
  bool _cameraOn = true;
  final Set<int> _seenSignalIds = {};
  final Map<String, DateTime> _lastOfferAt = {};
  final Map<String, String> _pcIds = {};
  final Map<String, DateTime> _offerSentAt = {};
  final Set<String> _offerBusy = {};
  String _viewerAcceptedPcId = '';
  int _bitrateRecalcTick = 0;

  bool get cameraOn => _cameraOn;
  int get viewerCount => _peers.length;
  static const int kMaxBroadcasters = 4;

  static int _targetKbps(int viewers) {
    if (viewers <= 2) return 1200;
    if (viewers <= 4) return 700;
    return 400;
  }

  Future<void> start() async {
    if (_closed) return;
    WakelockPlus.enable();
    await localRenderer.initialize();
    await remoteRenderer.initialize();

    _signalSub = _prv.onSignal(roomId).listen(_onSignal);
    await _fastForwardSignals();
    // Polling cadangan tiap 2 detik (pola call 1:1) — realtime insert
    // bisa terlewat, tanpa polling handshake bisa mati diam-diam.
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_syncMissedSignals());
    });

    if (isBroadcaster) {
      // Cap 4: cek jumlah broadcaster aktif sebelum ambil kamera
      final cnt = await _prv.broadcastCount(roomId);
      if (cnt >= kMaxBroadcasters) {
        debugPrint('[BROADCAST] cap 4 reached, abort start');
        await stop();
        throw Exception('Broadcast full (4/4)');
      }
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {'facingMode': 'user', 'width': 1280, 'height': 720},
        });
        localRenderer.srcObject = _localStream;
        localRendererReady = true;
        await _prv.startBroadcast(roomId);
      } catch (e) {
        debugPrint('[BROADCAST] getUserMedia/startBroadcast failed: $e');
        await stop();
        rethrow;
      }
      // Heartbeat tampilkan masih hidup
      _hbTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        if (_closed) return;
        try {
          await _sb.rpc('touch_broadcast', params: {'p_room_id': roomId});
        } catch (_) {}
      });
      // Recovery watchdog: dua kasus deadlock dijahit di sini —
      // (a) pc benar-benar gagal (Failed/Disconnected/Closed-stale)
      // (b) pc stuck have-local-offer > 8 detik (offer terkirim tapi answer
      //     tak pernah datang / ditolak) — tanpa ini deadlock menunggu
      //     cycle rejoin viewer yang lambat.
      _reOfferTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_closed || !isBroadcaster) return;
        for (final entry in _peers.entries.toList()) {
          final pc = entry.value;
          final st = pc.connectionState;
          final dead = st == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
              st == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
              st == RTCPeerConnectionState.RTCPeerConnectionStateClosed;
          if (st != null && dead) {
            debugPrint('[BROADCAST] re-offer to ${entry.key} state=$st');
            unawaited(_makeOfferTo(entry.key));
            continue;
          }
          final sentAt = _offerSentAt[entry.key];
          if (sentAt != null &&
              DateTime.now().difference(sentAt) > const Duration(seconds: 8)) {
            debugPrint('[BROADCAST] re-offer to ${entry.key} (no answer >8s)');
            unawaited(_makeOfferTo(entry.key));
          }
        }
      });
      // Subscribe perubahan broadcaster — hanya untuk menghitung ulang
      // bitrate saat JUMLAH peer berubah (bukan tiap heartbeat row).
      _broadcasterSub = _sb
          .channel('room-broadcasters-$roomId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'room_broadcasters',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'room_id',
              value: roomId,
            ),
            callback: (_) {
              // Debounce — heartbeat touch tiap 15s juga memicu event ini.
              _bitrateRecalcTick++;
              final tick = _bitrateRecalcTick;
              Future.delayed(const Duration(seconds: 2), () {
                if (!_closed && tick == _bitrateRecalcTick) {
                  _renegotiateBitrateAll();
                }
              });
            },
          )
          .subscribe();
      // All-together: broadcaster juga butuh lihat broadcaster lain
      await Future.delayed(const Duration(milliseconds: 400));
      await requestStream();
    } else {
      // Penonton: minta stream
      unawaited(_prv.requestJoin(roomId));
      await Future.delayed(const Duration(milliseconds: 200));
      await requestStream();
      // Watchdog: jika tidak ada broadcaster, stop
      _watchdog = Timer.periodic(const Duration(seconds: 10), (_) async {
        if (_closed) return;
        try {
          final cnt = await _prv.broadcastCount(roomId);
          if (cnt == 0) stop();
        } catch (_) {}
      });
      // Rejoin TANPA teardown: selama video belum masuk / koneksi mati,
      // kirim b_join baru tiap 5 detik → broadcaster re-offer (guard busy
      // mencegah spam) → viewer terima offer terbaru (pcId) → handshake
      // ulang → onTrack → video hidup. Session tidak dibongkar — tidak ada
      // fase blank di antara restart, screen stay di stage "menyambungkan".
      _rejoinTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (_closed || remoteReady) return;
        try {
          final cnt = await _prv.broadcastCount(roomId);
          if (cnt > 0) {
            debugPrint('[BROADCAST] viewer re-ping (no video yet)');
            await requestStream();
          }
        } catch (_) {}
      });
    }
    notifyListeners();
  }

  // ignore: unused_element
  Future<String?> _currentLiveUid() async {
    try {
      final row = await _sb.from('rooms').select('live_uid').eq('id', roomId).maybeSingle();
      return row?['live_uid']?.toString();
    } catch (_) {
      return null;
    }
  }

  void _onSignal(Map<String, dynamic> sig) {
    if (_closed) return;
    // Dedupe by signal id — realtime & polling bisa menyampaikan row yang
    // sama dua kali. Tanpa ini b_join/offer/answer dobel merusak handshake.
    final sid = (sig['id'] ?? 0) as num;
    final sidInt = sid.toInt();
    if (sidInt > 0) {
      if (!_seenSignalIds.add(sidInt)) return;
    }
    // Signal basi (replay dari DB / late realtime) diabaikan — mencegah
    // offer/answer lama merusak negosiasi WebRTC (video hitam).
    final ca = DateTime.tryParse('${sig['created_at'] ?? ''}');
    if (ca != null &&
        DateTime.now().toUtc().difference(ca.toUtc()) >
            const Duration(seconds: 30)) {
      return;
    }
    final type = '${sig['type'] ?? ''}';
    final from = '${sig['from_uid'] ?? ''}';
    final payload = (sig['payload'] as Map?)?.cast<String, dynamic>() ?? {};

    switch (type) {
      case 'b_join':
        // Guard busy ada di dalam _makeOfferTo — b_join dobel realtime+polling
        // maupun tumpang tindih watchdog tetap satu offer per viewer.
        if (isBroadcaster) {
          unawaited(_makeOfferTo(from));
        }
        break;
      case 'b_offer':
        // Guard SINKRON pakai timestamp: burst offer (replay + realtime)
        // harusnya hanya yang TERBARU diproses. Guard async di dalam
        // _viewerHandleOffer kalah race (semua offer masuk sebelum satu pun
        // selesai setRemoteDescription → 20 answer → pc broadcaster rusak).
        {
          final ca = DateTime.tryParse('${sig['created_at'] ?? ''}') ??
              DateTime.now().toUtc();
          final last = _lastOfferAt[from];
          if (last != null && !ca.isAfter(last)) {
            debugPrint('[BROADCAST] duplicate/stale offer ignored for $from');
            return;
          }
          _lastOfferAt[from] = ca;
          unawaited(_viewerHandleOffer(from, payload));
        }
        break;
      case 'b_answer':
        unawaited(_handleAnswer(from, payload));
        break;
      case 'b_cand':
        unawaited(_handleCandidate(from, payload));
        break;
      case 'b_bye':
        _dropPeer(from);
        break;
      case 'hand_raise':
        // diteruskan ke UI via notifyListeners, RoomMembersSheet bisa listen
        notifyListeners();
        break;
    }
  }

  Future<void> requestStream() async {
    if (_closed) return;
    await _prv.sendSignal(
      roomId,
      type: 'b_join',
      payload: {'ts': DateTime.now().toIso8601String()},
    );
  }

  /// Tunggu ICE gathering complete supaya semua kandidat TERKANDUNG di
  /// dalam SDP (non-trickle). Mencegah kelas bug "answer applied tapi ICE
  /// tidak pernah jalan" karena trickle candidate hilang di transit.
  /// Timeout 2 detik — kalau blom selesai, kirim apa adanya (trickle tetap
  /// jalan sebagai fallback).
  Future<void> _waitIceGathering(RTCPeerConnection pc) async {
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final completer = Completer<void>();
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };
    try {
      await completer.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      // timeout — kirim SDP apa adanya, trickle tetap fallback
    }
  }

  Future<void> _makeOfferTo(String viewerUid) async {
    // Guard tunggal di SEMUA jalur (b_join, recovery, deadlock): satu offer
    // berjalan per viewer. Tanpa ini b_join dobel → 2 pc paralel → answer
    // jatuh ke pc salah → kadang Connected kadang blank (race klasik).
    if (_offerBusy.contains(viewerUid)) return;
    _offerBusy.add(viewerUid);
    try {
      if (_localStream == null) return;
      final old = _peers[viewerUid];
      if (old != null) {
        try {
          await old.close();
        } catch (_) {}
      }
      _peers.remove(viewerUid);
      _pcIds.remove(viewerUid);
      _pendingCands.remove(viewerUid);
      final pc = await createPeerConnection(await CallConfig.getPeerConfig());
      _peers[viewerUid] = pc;

      await pc.addTrack(_localStream!.getVideoTracks().first, _localStream!);
      _applyBitrate(pc);

      pc.onIceCandidate = (c) {
        _prv.sendSignal(roomId, type: 'b_cand', toUid: viewerUid, payload: {
          'candidate': c.toMap(),
        });
      };
      pc.onConnectionState = (st) {
        debugPrint('[BROADCAST] peer $viewerUid state=$st');
        // Hanya proses event dari pc yang MASIH AKTIF di _peers — event
        // Closed dari pc lama yang baru diganti tidak boleh menghapus
        // pc baru (race re-offer yang dulu bikin video blank abadi).
        if (!identical(_peers[viewerUid], pc)) return;
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _dropPeer(viewerUid);
        }
        notifyListeners();
      };

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      // Non-trickle: tunggu kandidat terkumpul di SDP sebelum dikirim —
      // kandidat yang hilang di transit = ICE tidak pernah jalan (bug
      // re-enter: answer applied tapi pc Closed tanpa Connecting).
      await _waitIceGathering(pc);
      final desc = await pc.getLocalDescription();
      final pcId = 'pc_${DateTime.now().microsecondsSinceEpoch}';
      _pcIds[viewerUid] = pcId;
      _offerSentAt[viewerUid] = DateTime.now();
      await _prv.sendSignal(roomId, type: 'b_offer', toUid: viewerUid, payload: {
        'sdp': (desc ?? offer).toMap(),
        'pcId': pcId,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('[BROADCAST] offer to $viewerUid failed: $e');
    } finally {
      _offerBusy.remove(viewerUid);
    }
  }

  Future<void> _handleAnswer(String from, Map<String, dynamic> payload) async {
    final sdp = payload['sdp'] as Map<String, dynamic>?;
    final pc = _peers[from];
    debugPrint('[BROADCAST] b_answer from=$from hasPc=${pc != null} pcId=${payload['pcId']} expected=${_pcIds[from]}');
    if (!isBroadcaster || sdp == null || pc == null) return;
    // Binding: answer harus milik offer/pc TERAKHIR untuk viewer ini.
    // Answer dari pc lama (race 2 offer) ditolak — mencegah SDP mismatch.
    final pcId = '${payload['pcId'] ?? ''}';
    if (pcId.isNotEmpty && pcId != (_pcIds[from] ?? '')) {
      debugPrint('[BROADCAST] b_answer from stale pc ignored for $from');
      return;
    }
    // Guard state: answer hanya valid saat punya offer pending (have-local-offer).
    // Tanpa ini, answer basi/dobel → "wrong state: stable" dan peer hang.
    final local = await pc.getLocalDescription();
    debugPrint('[BROADCAST] b_answer local=${local?.type}');
    if (local == null || local.type != 'offer') return;
    final remote = await pc.getRemoteDescription();
    if (remote != null) {
      debugPrint('[BROADCAST] b_answer duplicate ignored for $from');
      return;
    }
    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type']),
      );
      debugPrint('[BROADCAST] b_answer applied for $from');
      _offerSentAt.remove(from);
      for (final c in List<Map<String, dynamic>>.from(_pendingCands[from] ?? const [])) {
        try {
          await pc.addCandidate(RTCIceCandidate(
            c['candidate'] ?? '',
            c['sdpMid'],
            (c['sdpMLineIndex'] as num?)?.toInt(),
          ));
        } catch (_) {}
      }
      _pendingCands.remove(from);
    } catch (e) {
      debugPrint('[BROADCAST] answer from $from failed: $e');
    }
  }

  Future<void> _handleCandidate(
    String from,
    Map<String, dynamic> payload,
  ) async {
    final c = payload['candidate'] as Map<String, dynamic>?;
    if (c == null) return;
    final pc = _peers[from];
    if (pc == null) {
      _pendingCands.putIfAbsent(from, () => []).add(c);
      return;
    }
    // Buffer sampai remote description terpasang — addCandidate saat masih
    // have-local-offer gagal diam-diam dan candidate hilang permanen
    // (root cause stuck "menyambungkan" tanpa error di log).
    try {
      final remote = await pc.getRemoteDescription();
      if (remote == null) {
        _pendingCands.putIfAbsent(from, () => []).add(c);
        return;
      }
    } catch (_) {
      _pendingCands.putIfAbsent(from, () => []).add(c);
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

  void _dropPeer(String uid) {
    final pc = _peers.remove(uid);
    try {
      pc?.close();
    } catch (_) {}
    final rr = remoteRenderers.remove(uid);
    try {
      rr?.dispose();
    } catch (_) {}
    _pendingCands.remove(uid);
    _pcIds.remove(uid);
    _offerSentAt.remove(uid);
    hasRemoteVideo = remoteRenderers.isNotEmpty;
    notifyListeners();
  }

  Future<void> _applyBitrate(RTCPeerConnection pc) async {
    final kbps = _targetKbps(_peers.length);
    try {
      final senders = await pc.getSenders();
      // Loop manual — firstWhere melempar "Bad state: No element" saat
      // sender belum ter-populate async (spam log + bitrate tak terpasang).
      for (final s in senders) {
        if (s.track?.kind == 'video') {
          final params = RTCRtpParameters(
            encodings: [
              RTCRtpEncoding(
                active: true,
                maxBitrate: kbps * 1000,
                minBitrate: (kbps * 0.5).round() * 1000,
              ),
            ],
          );
          await s.setParameters(params);
          break;
        }
      }
    } catch (_) {}
  }

  void _renegotiateBitrateAll() {
    for (final pc in _peers.values) {
      _applyBitrate(pc);
    }
  }

  Future<void> toggleCamera() async {
    if (_localStream == null) return;
    _cameraOn = !_cameraOn;
    for (final t in _localStream!.getVideoTracks()) {
      t.enabled = _cameraOn;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    try {
      final tracks = _localStream?.getVideoTracks() ?? [];
      if (tracks.isNotEmpty) {
        await Helper.switchCamera(tracks.first);
      }
    } catch (e) {
      debugPrint('[BROADCAST] switchCamera error: $e');
    }
  }

  Future<void> _viewerHandleOffer(
    String broadcasterUid,
    Map<String, dynamic> payload,
  ) async {
    final sdp = payload['sdp'] as Map<String, dynamic>?;
    if (sdp == null) return;
    // Dedupe pakai pcId: offer dengan pcId BARU = re-offer sah, harus
    // diproses (ganti pc lama). pcId LAMA/sama = replay, ditolak.
    // (Guard getRemoteDescription lama salah menolak re-offer valid →
    // broadcaster tak pernah dapat answer → video blank abadi.)
    final offerPcId = '${payload['pcId'] ?? ''}';
    if (offerPcId.isNotEmpty && offerPcId == _viewerAcceptedPcId) {
      debugPrint('[BROADCAST] duplicate offer (same pcId) ignored');
      return;
    }
    try {
      var pc = _peers[broadcasterUid];
      if (pc != null) {
        try {
          await pc.close();
        } catch (_) {}
        _peers.remove(broadcasterUid);
      }
      pc = await createPeerConnection(await CallConfig.getPeerConfig());
      _peers[broadcasterUid] = pc;
      _viewerAcceptedPcId = offerPcId;
      // Negosiasi baru → video lama tidak boleh dianggap "siap" lagi.
      remoteReady = false;

      pc.onConnectionState = (st) {
        debugPrint('[BROADCAST] viewer pc state=$st');
        // Guard identitas: event dari pc lama (yang diganti re-offer) tidak
        // boleh me-reset status pc baru.
        if (!identical(_peers[broadcasterUid], pc)) return;
        // Koneksi mati → video beku. Reset remoteReady supaya rejoin ping
        // jalan lagi (tanpa ini viewer menonton layar beku selamanya).
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          remoteReady = false;
          notifyListeners();
        }
      };

      pc.onTrack = (event) async {
        final stream =
            event.streams.isNotEmpty ? event.streams.first : null;
        if (stream != null && !_closed) {
          remoteRenderer.srcObject = stream;
          var r = remoteRenderers[broadcasterUid];
          if (r == null) {
            r = RTCVideoRenderer();
            await r.initialize();
            remoteRenderers[broadcasterUid] = r;
          }
          r.srcObject = stream;
          hasRemoteVideo = remoteRenderers.values.any((rr) => rr.srcObject != null);
          remoteReady = true;
          notifyListeners();
        }
      };
      pc.onIceCandidate = (c) {
        _prv.sendSignal(roomId, type: 'b_cand', toUid: broadcasterUid,
            payload: {'candidate': c.toMap()});
      };

      await pc.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type']),
      );
      // Flush candidate broadcaster yang antri sebelum offer diproses
      // (broadcaster _handleAnswer punya ini; viewer terlewat → ICE gagal).
      for (final c in List<Map<String, dynamic>>.from(
          _pendingCands[broadcasterUid] ?? const [])) {
        try {
          await pc.addCandidate(RTCIceCandidate(
            c['candidate'] ?? '',
            c['sdpMid'],
            (c['sdpMLineIndex'] as num?)?.toInt(),
          ));
        } catch (_) {}
      }
      _pendingCands.remove(broadcasterUid);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      // Non-trickle: kandidat viewer ikut dalam SDP answer — broadcaster
      // tidak menunggu trickle yang bisa hilang.
      await _waitIceGathering(pc);
      final desc = await pc.getLocalDescription();
      await _prv.sendSignal(roomId, type: 'b_answer', toUid: broadcasterUid,
          payload: {'sdp': (desc ?? answer).toMap(), 'pcId': payload['pcId'] ?? ''});
      debugPrint('[BROADCAST] viewer answered $broadcasterUid pcId=${payload['pcId']}');
    } catch (e) {
      debugPrint('[BROADCAST] viewer offer failed: $e');
    }
  }

  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    WakelockPlus.disable();
    _hbTimer?.cancel();
    _watchdog?.cancel();
    _syncTimer?.cancel();
    _rejoinTimer?.cancel();
    _reOfferTimer?.cancel();
    await _signalSub?.cancel();
    if (_broadcasterSub != null) {
      _sb.removeChannel(_broadcasterSub!);
      _broadcasterSub = null;
    }
    if (isBroadcaster) {
      await _prv.sendSignal(roomId, type: 'b_bye');
      try {
        await _prv.stopBroadcastV2(roomId);
      } catch (_) {}
    } else {
      // Viewer juga beri tahu broadcaster agar pc basi di-drop — tanpa ini
      // re-join (keluar-masuk room) diabaikan selamanya → video blank.
      await _prv.sendSignal(roomId, type: 'b_bye');
    }
    for (final pc in _peers.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _peers.clear();
    for (final r in remoteRenderers.values) {
      try {
        await r.dispose();
      } catch (_) {}
    }
    remoteRenderers.clear();
    try {
      await localRenderer.dispose();
    } catch (_) {}
    try {
      await remoteRenderer.dispose();
    } catch (_) {}
    onEnded?.call();
    notifyListeners();
  }

  Future<void> _syncMissedSignals() async {
    if (_closed) return;
    try {
      final rows = await _prv.fetchSignalsSince(roomId, _lastSignalId);
      for (final r in rows) {
        _lastSignalId = max(_lastSignalId, ((r['id'] ?? 0) as num).toInt());
        _onSignal(r);
      }
    } catch (_) {}
  }

  /// Cursor maju ke id signal TERBESAR saat session dimulai — offer/answer
  /// lama dari session sebelumnya tidak boleh di-replay (penyebab video
  /// blank saat keluar-masuk room). Signal baru (id > cursor) saja yang
  /// diproses polling.
  Future<void> _fastForwardSignals() async {
    try {
      final row = await _sb
          .from('room_signals')
          .select('id')
          .eq('room_id', roomId)
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();
      _lastSignalId = ((row?['id'] ?? 0) as num).toInt();
      debugPrint('[BROADCAST] signal cursor fast-forward to $_lastSignalId');
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
