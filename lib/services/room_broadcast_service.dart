import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
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
  int _lastSignalId = 0;
  bool _closed = false;
  bool _cameraOn = true;

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
    await localRenderer.initialize();
    await remoteRenderer.initialize();

    _signalSub = _prv.onSignal(roomId).listen(_onSignal);
    unawaited(_seedMissedSignals());

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
      // Subscribe perubahan broadcaster untuk bitrate adaptif
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
            callback: (_) => _renegotiateBitrateAll(),
          )
          .subscribe();
      // All-together: broadcaster juga butuh lihat broadcaster lain
      await Future.delayed(const Duration(milliseconds: 400));
      await requestStream();
    } else {
      // Penonton: minta stream
      unawaited(_prv.requestJoin(roomId));
      await Future.delayed(const Duration(milliseconds: 600));
      await requestStream();
      // Watchdog: jika tidak ada broadcaster, stop
      _watchdog = Timer.periodic(const Duration(seconds: 10), (_) async {
        if (_closed) return;
        try {
          final cnt = await _prv.broadcastCount(roomId);
          if (cnt == 0) stop();
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
    final type = '${sig['type'] ?? ''}';
    final from = '${sig['from_uid'] ?? ''}';
    final payload = (sig['payload'] as Map?)?.cast<String, dynamic>() ?? {};

    switch (type) {
      case 'b_join':
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
    final rr = remoteRenderers.remove(uid);
    try {
      rr?.dispose();
    } catch (_) {}
    _pendingCands.remove(uid);
    hasRemoteVideo = remoteRenderers.isNotEmpty;
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
    if (_broadcasterSub != null) {
      _sb.removeChannel(_broadcasterSub!);
      _broadcasterSub = null;
    }
    if (isBroadcaster) {
      await _prv.sendSignal(roomId, type: 'b_bye');
      try {
        await _prv.stopBroadcastV2(roomId);
      } catch (_) {}
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
