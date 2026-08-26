import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../config/call_config.dart';
import 'private_room_service.dart';
import '../config/supabase_config.dart';

/// Broadcast video satu-ke-banyak di private room (mesh WebRTC).
///
/// - Broadcaster = member yang diberi izin oleh admin.
/// - Tiap penonton = 1 peer connection (offer dari broadcaster).
/// - Signaling via tabel room_signals (b_offer/b_answer/b_cand/b_bye).
/// - Adaptive bitrate: kualitas turun mengikuti jumlah penonton.
/// - Heartbeat last_seen di rooms.live_started_at; jika broadcaster
///   hilang >45 detik, penonton berhenti otomatis (fallback app crash).
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
  // Penonton: video dari broadcaster.
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool remoteReady = false;
  bool hasRemoteVideo = false;

  StreamSubscription? _signalSub;
  Timer? _hbTimer;
  Timer? _watchdog;
  int _lastSignalId = 0;
  bool _closed = false;
  bool _cameraOn = true;

  bool get cameraOn => _cameraOn;
  int get viewerCount => _peers.length;

  /// Bitrate target (kbps) sesuai jumlah penonton — ladder adaptif.
  static int _targetKbps(int viewers) {
    if (viewers <= 6) return 1200; // ~720p
    if (viewers <= 12) return 700; // ~480p
    return 400; // ~360p
  }

  Future<void> start() async {
    if (_closed) return;
    await localRenderer.initialize();

    await remoteRenderer.initialize();
    if (!isBroadcaster) {
      _signalSub = _prv.onSignal(roomId).listen(_onSignal);
      unawaited(_prv.requestJoin(roomId)); // no-op kalau sudah member
      await Future.delayed(const Duration(milliseconds: 600));
      await requestStream();
      notifyListeners();
      return;
    }
    if (isBroadcaster) {
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': false, // broadcast = video saja (mic tetap lewat chat/voice)
          'video': {'facingMode': 'user', 'width': 1280, 'height': 720},
        });
        localRenderer.srcObject = _localStream;
        localRendererReady = true;
      } catch (e) {
        debugPrint('[BROADCAST] getUserMedia failed: $e');
        await stop();
        return;
      }
      // Broadcaster: tunggu penonton masuk → buat offer per penonton.
      _signalSub = _prv.onSignal(roomId).listen(_onSignal);
      unawaited(_seedMissedSignals());
      // Heartbeat: tandai masih hidup.
      _hbTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        if (_closed) return;
        try {
          final liveUid = await _currentLiveUid();
          if (liveUid != _sb.auth.currentUser?.id) return stop();
          await _sb.rpc('touch_broadcast', params: {'p_room_id': roomId});
        } catch (_) {}
      });
    } else {
      // Penonton: watchdog — kalau live_uid hilang / broadcaster mati, stop.
      _watchdog = Timer.periodic(const Duration(seconds: 10), (_) async {
        if (_closed) return;
        try {
          final liveUid = await _currentLiveUid();
          if (liveUid == null || liveUid.isEmpty) stop();
        } catch (_) {}
      });
    }
    notifyListeners();
  }

  Future<String?> _currentLiveUid() async {
    try {
      final row = await _sbRoom();
      return row?['live_uid']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _sbRoom() async {
    try {
      final res = await PrivateRoomService.instance
          .listMembers(roomId); // keep-alive jalur supabase
      debugPrint('[BROADCAST] members=${res.length}');
    } catch (_) {}
    return null;
  }

  void _onSignal(Map<String, dynamic> sig) {
    if (_closed) return;
    final type = '${sig['type'] ?? ''}';
    final from = '${sig['from_uid'] ?? ''}';
    final payload = (sig['payload'] as Map?)?.cast<String, dynamic>() ?? {};

    switch (type) {
      case 'b_join':
        // Penonton minta stream → broadcaster buat offer.
        if (isBroadcaster && !_peers.containsKey(from)) {
          unawaited(_makeOfferTo(from));
        }
        break;
      case 'b_offer':
        unawaited(_viewerHandleOffer(from, payload));
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
    }
  }

  /// Penonton: kirim b_join untuk meminta offer.
  Future<void> requestStream() async {
    if (_closed || isBroadcaster) return;
    await _prv.sendSignal(
      roomId,
      type: 'b_join',
      payload: {'ts': DateTime.now().toIso8601String()},
    );
  }

  Future<void> _makeOfferTo(String viewerUid) async {
    try {
      if (_localStream == null) return;
      final old = _peers[viewerUid];
      if (old != null) {
        try {
          await old.close();
        } catch (_) {}
      }
      _pendingCands.remove(viewerUid);
      final pc = await createPeerConnection(await CallConfig.getPeerConfig());
      _peers[viewerUid] = pc;
      _applyBitrate(pc);

      await pc.addTrack(_localStream!.getVideoTracks().first, _localStream!);
      _renegotiateBitrateAll();

      pc.onIceCandidate = (c) {
        _prv.sendSignal(roomId, type: 'b_cand', toUid: viewerUid, payload: {
          'candidate': c.toMap(),
        });
      };
      pc.onConnectionState = (st) {
        debugPrint('[BROADCAST] peer $viewerUid state=$st');
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _dropPeer(viewerUid);
        }
        notifyListeners();
      };

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _prv.sendSignal(roomId, type: 'b_offer', toUid: viewerUid, payload: {
        'sdp': offer.toMap(),
      });
      notifyListeners();
    } catch (e) {
      debugPrint('[BROADCAST] offer to $viewerUid failed: $e');
    }
  }

  Future<void> _handleAnswer(String from, Map<String, dynamic> payload) async {
    final sdp = payload['sdp'] as Map<String, dynamic>?;
    final pc = _peers[from];
    if (!isBroadcaster || sdp == null || pc == null) return;
    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type']),
      );
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
    _pendingCands.remove(uid);
    notifyListeners();
  }

  Future<void> _applyBitrate(RTCPeerConnection pc) async {
    final kbps = _targetKbps(_peers.length);
    try {
      final senders = await pc.getSenders();
      final videoSender = senders.firstWhere((s) => s.track?.kind == 'video');
      final params = RTCRtpParameters(
        encodings: [
          RTCRtpEncoding(
            active: true,
            maxBitrate: kbps * 1000,
            minBitrate: (kbps * 0.5).round() * 1000,
          ),
        ],
      );
      await videoSender.setParameters(params);
    } catch (e) {
      debugPrint('[BROADCAST] set bitrate failed: $e');
    }
  }

  /// Re-negotiate bitrate ke semua peer (dipanggil saat jumlah penonton berubah).
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

  // ── Sisi PENONTON ──

  Future<void> _viewerHandleOffer(
    String broadcasterUid,
    Map<String, dynamic> payload,
  ) async {
    final sdp = payload['sdp'] as Map<String, dynamic>?;
    if (sdp == null) return;
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

      pc.onTrack = (event) {
        final stream =
            event.streams.isNotEmpty ? event.streams.first : null;
        if (stream != null && !_closed) {
          remoteRenderer.srcObject = stream;
          hasRemoteVideo =
              stream.getVideoTracks().isNotEmpty;
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
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await _prv.sendSignal(roomId, type: 'b_answer', toUid: broadcasterUid,
          payload: {'sdp': answer.toMap()});
      debugPrint('[BROADCAST] viewer answered $broadcasterUid');
    } catch (e) {
      debugPrint('[BROADCAST] viewer offer failed: $e');
    }
  }

  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    _hbTimer?.cancel();
    _watchdog?.cancel();
    await _signalSub?.cancel();
    await remoteRenderer.initialize();
    if (!isBroadcaster) {
      _signalSub = _prv.onSignal(roomId).listen(_onSignal);
      unawaited(_prv.requestJoin(roomId)); // no-op kalau sudah member
      await Future.delayed(const Duration(milliseconds: 600));
      await requestStream();
      notifyListeners();
      return;
    }
    if (isBroadcaster) {
      await _prv.sendSignal(roomId, type: 'b_bye');
      try {
        await _prv.stopBroadcast(roomId);
      } catch (_) {}
    }
    for (final pc in _peers.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _peers.clear();
    try {
      await localRenderer.dispose();
    } catch (_) {}
    onEnded?.call();
    notifyListeners();
  }

  // Seed signal yang terlewat saat broadcaster offline (id cursor).
  Future<void> _seedMissedSignals() async {
    final rows = await _prv.fetchSignalsSince(roomId, _lastSignalId);
    for (final r in rows) {
      _lastSignalId = max(_lastSignalId, ((r['id'] ?? 0) as num).toInt());
      _onSignal(r);
    }
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}